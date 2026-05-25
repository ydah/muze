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

  describe ".resolve" do
    it "accepts array windows" do
      expect(described_class.resolve([0.0, 1.0, 0.0], 3).to_a).to eq([0.0, 1.0, 0.0])
    end

    it "accepts proc windows" do
      expect(described_class.resolve(->(n) { Array.new(n, 0.5) }, 2).to_a).to eq([0.5, 0.5])
    end

    it "supports additional built-in windows" do
      expect(described_class.resolve(:kaiser, 8).size).to eq(8)
      expect(described_class.resolve(:tukey, 8).size).to eq(8)
      expect(described_class.resolve(:blackman_harris, 8).size).to eq(8)
    end
  end
end
