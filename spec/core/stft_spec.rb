# frozen_string_literal: true

RSpec.describe Muze::Core::STFT do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(4096) do |index|
        Math.sin((2.0 * Math::PI * 440.0 * index) / sr)
      end
    )
  end

  describe ".stft" do
    it "returns expected shape" do
      result = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false)

      expect(result.shape).to eq([129, 61])
    end

    it "changes frame count with center" do
      centered = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      uncentered = Muze.stft(signal, n_fft: 256, hop_length: 64, center: false)

      expect(centered.shape[1]).to be > uncentered.shape[1]
    end
  end

  describe ".istft" do
    it "reconstructs waveform with small error" do
      spectrum = Muze.stft(signal, n_fft: 256, hop_length: 64, center: true)
      reconstructed = Muze.istft(spectrum, hop_length: 64, center: true, length: signal.size)

      error = (reconstructed - signal).abs.max
      expect(error).to be < 0.05
    end
  end

  describe "dB conversion" do
    it "is invertible for amplitude" do
      amplitude = Numo::SFloat[[0.1, 0.5, 1.0, 2.0]]
      db = Muze.amplitude_to_db(amplitude, ref: 1.0, top_db: nil)
      restored = Muze.db_to_amplitude(db, ref: 1.0)

      error = (restored - amplitude).abs.max
      expect(error).to be < 1.0e-4
    end
  end
end
