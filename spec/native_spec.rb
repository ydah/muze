# frozen_string_literal: true

RSpec.describe Muze::Native do
  describe ".median1d" do
    it "matches the upper median from sorted values" do
      values = [4.0, 1.0, 9.0, 2.0, 3.0]

      expect(described_class.median1d(values)).to eq(values.sort[values.length / 2])
    end

    it "returns zero for empty input" do
      expect(described_class.median1d([])).to eq(0.0)
    end
  end

  describe ".frame_slices" do
    it "matches Core::Frames slicing for unpadded frames" do
      native = described_class.frame_slices([1, 2, 3, 4, 5], 3, 2)
      shared = Muze::Core::Frames.slice([1, 2, 3, 4, 5], frame_length: 3, hop_length: 2)

      expect(native).to eq(shared)
    end
  end
end
