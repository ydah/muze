# frozen_string_literal: true

RSpec.describe Muze::Core::Windows do
  describe ".hann" do
    it "returns symmetric values" do
      window = described_class.hann(8).to_a

      expect(window.length).to eq(8)
      expect(window.first).to be_within(1.0e-6).of(0.0)
      expect(window[1]).to be_within(1.0e-6).of(window[-2])
    end
  end

  describe ".hamming" do
    it "returns expected edge values" do
      window = described_class.hamming(8).to_a

      expect(window.first).to be_within(1.0e-6).of(0.08)
      expect(window[2]).to be_within(1.0e-6).of(window[-3])
    end
  end

  describe ".blackman" do
    it "returns symmetric values" do
      window = described_class.blackman(8).to_a

      expect(window[1]).to be_within(1.0e-6).of(window[-2])
    end
  end

  describe ".ones" do
    it "returns ones" do
      window = described_class.ones(4)

      expect(window.to_a).to eq([1.0, 1.0, 1.0, 1.0])
    end
  end
end
