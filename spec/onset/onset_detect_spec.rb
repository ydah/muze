# frozen_string_literal: true

RSpec.describe Muze::Onset do
  let(:sr) { 22_050 }
  let(:hop_length) { 256 }
  let(:click_signal) do
    signal = Array.new(sr * 2, 0.0)
    [0.25, 0.75, 1.25, 1.75].each do |second|
      center = (second * sr).to_i
      128.times do |offset|
        index = center + offset
        break if index >= signal.length

        signal[index] = Math.sin((Math::PI * offset) / 128.0)
      end
    end
    Numo::SFloat.cast(signal)
  end

  describe ".onset_strength" do
    it "returns non-negative envelope" do
      envelope = described_class.onset_strength(y: click_signal, sr:, hop_length:, n_fft: 1024)

      expect(envelope.to_a.all? { |value| value >= 0.0 }).to be(true)
    end
  end

  describe ".onset_detect" do
    it "detects multiple click onsets" do
      onsets = described_class.onset_detect(y: click_signal, sr:, hop_length:, backtrack: false)

      expect(onsets.length).to be >= 3
    end

    it "moves indices earlier with backtrack" do
      onset_envelope = described_class.onset_strength(y: click_signal, sr:, hop_length:, n_fft: 1024)
      regular = described_class.onset_detect(onset_envelope:, hop_length:, backtrack: false)
      backtracked = described_class.onset_detect(onset_envelope:, hop_length:, backtrack: true)

      expect(backtracked.zip(regular).all? { |a, b| a <= b }).to be(true)
    end

    it "supports :samples units and aligns with :frames/:time" do
      onset_envelope = described_class.onset_strength(y: click_signal, sr:, hop_length:, n_fft: 1024)
      frames = described_class.onset_detect(onset_envelope:, hop_length:, units: :frames)
      samples = described_class.onset_detect(onset_envelope:, hop_length:, units: :samples)
      times = described_class.onset_detect(onset_envelope:, sr:, hop_length:, units: :time)

      expect(samples).to eq(frames.map { |frame| frame * hop_length })
      expect(times.zip(samples).all? { |time, sample| ((time * sr) - sample).abs <= 1.0e-6 }).to be(true)
    end
  end
end
