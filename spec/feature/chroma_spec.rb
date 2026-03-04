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
  end
end
