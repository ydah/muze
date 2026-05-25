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

    it "can return masks and validates parameters" do
      signal = mixed_signal
      result = described_class.hpss(signal, kernel_size: 9, margin: [1.0, 2.0], n_fft: 1024, hop_length: 256, return_masks: true)

      expect(result.length).to eq(4)
      expect do
        described_class.hpss(signal, kernel_size: 10)
      end.to raise_error(Muze::ParameterError, /kernel_size/)
      expect do
        described_class.hpss([0.0, Float::NAN])
      end.to raise_error(Muze::ParameterError, /finite/)
      expect do
        described_class.hpss(signal, return_masks: :yes)
      end.to raise_error(Muze::ParameterError, /return_masks/)
    end

    it "processes multi-channel input channel-wise" do
      signal = mixed_signal
      stereo = Numo::SFloat.zeros(signal.size, 2)
      stereo[true, 0] = signal
      stereo[true, 1] = signal * 0.5

      harmonic, percussive, harmonic_masks, percussive_masks = described_class.hpss(stereo, kernel_size: 9, n_fft: 1024, hop_length: 256, return_masks: true)

      expect(harmonic.shape).to eq(stereo.shape)
      expect(percussive.shape).to eq(stereo.shape)
      expect(harmonic_masks.length).to eq(2)
      expect(percussive_masks.length).to eq(2)
    end

    it "streams harmonic and percussive chunks" do
      signal = mixed_signal
      chunks = [signal[0...4096], signal[4096...8192]]
      streamed = described_class.hpss_stream(chunks, kernel_size: 9, n_fft: 512, hop_length: 128, overlap: 256).to_a

      expect(streamed.length).to eq(2)
      expect(streamed.sum { |harmonic, _percussive| harmonic.size }).to eq(chunks.sum(&:size))
      expect(streamed.all? { |harmonic, percussive| harmonic.size == percussive.size }).to be(true)
    end
  end
end
