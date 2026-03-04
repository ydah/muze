# frozen_string_literal: true

RSpec.describe Muze::Filters do
  describe ".chroma" do
    it "returns expected shape" do
      bank = described_class.chroma(sr: 22_050, n_fft: 2048, n_chroma: 12)

      expect(bank.shape).to eq([12, 1025])
    end

    it "maps 440Hz close to A chroma" do
      n_fft = 4096
      sr = 22_050
      bank = described_class.chroma(sr:, n_fft:, n_chroma: 12)
      bin = ((440.0 * n_fft) / sr).round
      weights = bank[true, bin].to_a
      dominant = weights.each_with_index.max_by(&:first)[1]

      expect(dominant).to eq(9)
    end
  end
end
