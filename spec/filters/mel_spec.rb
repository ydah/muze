# frozen_string_literal: true

RSpec.describe Muze::Filters do
  describe ".mel" do
    it "returns expected shape" do
      bank = described_class.mel(sr: 22_050, n_fft: 2048, n_mels: 64)

      expect(bank.shape).to eq([64, 1025])
    end

    it "has non-negative row sums" do
      bank = described_class.mel(sr: 22_050, n_fft: 2048, n_mels: 16)

      sums = bank.sum(1).to_a
      expect(sums.all? { |value| value >= 0.0 }).to be(true)
    end
  end

  describe "mel conversion" do
    it "is approximately invertible" do
      hz = 4400.0
      mel = described_class.hz_to_mel(hz)
      restored = described_class.mel_to_hz(mel)

      expect(restored).to be_within(1.0e-3).of(hz)
    end
  end
end
