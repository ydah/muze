# frozen_string_literal: true

RSpec.describe Muze::Feature do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(sr) { |index| Math.sin((2.0 * Math::PI * 440.0 * index) / sr) }
    )
  end

  describe ".chroma_stft" do
    it "returns [n_chroma, frames]" do
      chroma = described_class.chroma_stft(y: signal, sr:, n_chroma: 12, n_fft: 2048, hop_length: 256)

      expect(chroma.shape[0]).to eq(12)
      expect(chroma.shape[1]).to be > 0
    end

    it "has strongest energy near A for 440Hz sine" do
      chroma = described_class.chroma_stft(y: signal, sr:, n_chroma: 12, n_fft: 4096, hop_length: 512)
      mean = chroma.mean(1).to_a
      dominant = mean.each_with_index.max_by(&:first)[1]

      expect(dominant).to eq(9)
    end

    it "passes tuning and rejects unsupported normalization" do
      tuned = described_class.chroma_stft(y: signal, sr:, n_chroma: 12, n_fft: 2048, hop_length: 256, tuning: 0.25)

      expect(tuned.shape[0]).to eq(12)
      expect do
        described_class.chroma_stft(y: signal, sr:, norm: :bad)
      end.to raise_error(Muze::ParameterError, /norm/)
    end

    it "supports octave weighting parameters" do
      chroma = described_class.chroma_stft(y: signal, sr:, n_chroma: 12, n_fft: 2048, hop_length: 256, ctroct: 5.0, octwidth: 2.0)

      expect(chroma.shape[0]).to eq(12)
      expect(chroma.to_a.flatten.all?(&:finite?)).to be(true)
    end

    it "rejects invalid precomputed spectrogram input" do
      expect do
        described_class.chroma_stft(sr:, s: Numo::SFloat[[-1.0]], n_fft: 2048)
      end.to raise_error(Muze::ParameterError, /non-negative/)
    end
  end

  describe ".tonnetz" do
    it "projects 12-bin chroma to six tonal centroid dimensions" do
      chroma = described_class.chroma_stft(y: signal, sr:, n_chroma: 12, n_fft: 2048, hop_length: 256)
      tonnetz = described_class.tonnetz(chroma:)

      expect(tonnetz.shape).to eq([6, chroma.shape[1]])
    end
  end
end
