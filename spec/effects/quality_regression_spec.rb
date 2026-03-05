# frozen_string_literal: true

RSpec.describe "Effects quality regression pack" do
  let(:sr) { 22_050 }

  let(:harmonic_signal) do
    duration = 2.0
    sample_count = (sr * duration).to_i
    samples = Array.new(sample_count) do |index|
      t = index.to_f / sr
      (0.7 * Math.sin(2.0 * Math::PI * 440.0 * t)) + (0.4 * Math.sin(2.0 * Math::PI * 660.0 * t))
    end
    Numo::SFloat.cast(samples)
  end

  let(:click_signal) do
    duration = 2.0
    sample_count = (sr * duration).to_i
    signal = Array.new(sample_count, 0.0)
    [0.2, 0.6, 1.0, 1.4, 1.8].each do |seconds|
      center = (seconds * sr).to_i
      signal[center] = 1.0 if center < signal.length
    end
    Numo::SFloat.cast(signal)
  end

  describe "time_stretch" do
    it "keeps dominant frequency stable for harmonic signals" do
      original_peak = SpecEffectQualityMetrics.dominant_frequency(harmonic_signal, sr:)
      fast_peak = SpecEffectQualityMetrics.dominant_frequency(Muze.time_stretch(harmonic_signal, rate: 2.0), sr:)
      slow_peak = SpecEffectQualityMetrics.dominant_frequency(Muze.time_stretch(harmonic_signal, rate: 0.5), sr:)

      expect(fast_peak).to be_within(20.0).of(original_peak)
      expect(slow_peak).to be_within(20.0).of(original_peak)
    end

    it "keeps transient positions close to expected scaling" do
      original_positions = SpecEffectQualityMetrics.click_positions(click_signal, threshold: 0.95)
      stretched_positions = SpecEffectQualityMetrics.click_positions(
        Muze.time_stretch(click_signal, rate: 2.0),
        threshold: 0.95
      )

      expected_positions = original_positions.map { |position| (position / 2.0).round }
      compared = stretched_positions.zip(expected_positions).take(4)

      expect(compared.all? { |actual, expected| (actual - expected).abs <= 256 }).to be(true)
    end
  end

  describe "pitch_shift" do
    it "shifts harmonic peaks by one octave at +12 semitones" do
      shifted = Muze.pitch_shift(harmonic_signal, sr:, n_steps: 12.0)
      peaks = SpecEffectQualityMetrics.top_frequencies(shifted, sr:, count: 4)

      expect(peaks.any? { |freq| (freq - 880.0).abs <= 25.0 }).to be(true)
      expect(peaks.any? { |freq| (freq - 1320.0).abs <= 35.0 }).to be(true)
    end
  end
end
