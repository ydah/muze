# frozen_string_literal: true

RSpec.describe Muze::Effects do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(sr) { |index| Math.sin((2.0 * Math::PI * 440.0 * index) / sr) }
    )
  end
  let(:long_signal) do
    duration = 2.0
    sample_count = (sr * duration).to_i
    Numo::SFloat.cast(
      Array.new(sample_count) { |index| Math.sin((2.0 * Math::PI * 440.0 * index) / sr) }
    )
  end

  describe ".time_stretch" do
    it "changes output length by rate" do
      stretched = described_class.time_stretch(signal, rate: 2.0)

      expect(stretched.size).to be_within(1).of(signal.size / 2)
    end

    it "keeps the signal unchanged at rate=1.0" do
      stretched = described_class.time_stretch(signal, rate: 1.0)
      max_error = (stretched - signal).abs.max

      expect(max_error).to be < 1.0e-6
    end

    it "preserves dominant frequency better than linear interpolation baseline" do
      stretched = described_class.time_stretch(long_signal, rate: 2.0)
      baseline = naive_linear_time_stretch(long_signal, rate: 2.0)

      phase_vocoder_peak = SpecEffectQualityMetrics.dominant_frequency(stretched, sr:)
      baseline_peak = SpecEffectQualityMetrics.dominant_frequency(baseline, sr:)

      expect((phase_vocoder_peak - 440.0).abs).to be < (baseline_peak - 440.0).abs
      expect(phase_vocoder_peak).to be_within(12.0).of(440.0)
    end
  end

  describe ".pitch_shift" do
    it "keeps output length" do
      shifted = described_class.pitch_shift(signal, sr:, n_steps: 4)

      expect(shifted.size).to eq(signal.size)
    end

    it "shifts 440Hz close to 880Hz for +12 semitones" do
      shifted = described_class.pitch_shift(long_signal, sr:, n_steps: 12.0)
      peak = SpecEffectQualityMetrics.dominant_frequency(shifted, sr:)

      expect(peak).to be_within(20.0).of(880.0)
    end

    it "supports fractional n_steps" do
      shifted = described_class.pitch_shift(signal, sr:, n_steps: 0.5)

      expect(shifted.size).to eq(signal.size)
      expect(shifted.to_a.all?(&:finite?)).to be(true)
    end
  end

  describe ".trim" do
    it "cuts leading and trailing silence" do
      padded = Numo::SFloat.zeros(signal.size + 4000)
      padded[2000...(2000 + signal.size)] = signal

      trimmed, (start_idx, end_idx) = described_class.trim(padded, top_db: 30)

      expect(trimmed.size).to be <= padded.size
      expect(start_idx).to be > 0
      expect(end_idx).to be > start_idx
    end
  end

  def naive_linear_time_stretch(y, rate:)
    source = y.to_a
    target_length = [(source.length / rate).round, 1].max

    stretched = Array.new(target_length, 0.0)
    target_length.times do |index|
      source_position = index * rate
      left = source_position.floor
      right = [left + 1, source.length - 1].min
      alpha = source_position - left
      stretched[index] = ((1.0 - alpha) * source[left]) + (alpha * source[right])
    end

    Numo::SFloat.cast(stretched)
  end

end
