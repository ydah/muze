# frozen_string_literal: true

RSpec.describe Muze::Effects do
  let(:sr) { 22_050 }

  def mixed_signal
    samples = sr
    signal = Array.new(samples, 0.0)

    samples.times do |idx|
      signal[idx] += 0.5 * Math.sin((2.0 * Math::PI * 440.0 * idx) / sr)
    end

    [0.2, 0.4, 0.6, 0.8].each do |second|
      center = (second * sr).to_i
      80.times do |offset|
        index = center + offset
        break if index >= signal.length

        signal[index] += Math.exp(-offset / 16.0)
      end
    end

    Numo::SFloat.cast(signal)
  end

  describe ".hpss" do
    it "roughly reconstructs original signal" do
      signal = mixed_signal
      harmonic, percussive = described_class.hpss(signal, kernel_size: 11, n_fft: 1024, hop_length: 256)
      reconstructed = harmonic + percussive

      error = (reconstructed - signal).abs.mean
      expect(error).to be < 0.1
    end

    it "keeps sine as mostly harmonic" do
      signal = Numo::SFloat.cast(Array.new(sr) { |idx| Math.sin((2.0 * Math::PI * 440.0 * idx) / sr) })
      harmonic, percussive = described_class.hpss(signal, kernel_size: 9, n_fft: 1024, hop_length: 256)

      expect(harmonic.abs.mean).to be > percussive.abs.mean
    end

    it "keeps clicks as mostly percussive" do
      signal = Numo::SFloat.zeros(sr)
      [0.2, 0.5, 0.8].each do |sec|
        idx = (sec * sr).to_i
        signal[idx...(idx + 40)] = 1.0
      end

      harmonic, percussive = described_class.hpss(signal, kernel_size: 9, n_fft: 1024, hop_length: 256)
      expect(percussive.abs.mean).to be > harmonic.abs.mean
    end
  end
end
