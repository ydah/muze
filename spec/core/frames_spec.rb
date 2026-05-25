# frozen_string_literal: true

RSpec.describe Muze::Core::Frames do
  describe ".slice" do
    it "slices full frames without trailing padding by default" do
      frames = described_class.slice([1, 2, 3, 4, 5], frame_length: 3, hop_length: 2)

      expect(frames).to eq([[1, 2, 3], [3, 4, 5]])
    end

    it "pads the final frame when requested" do
      frames = described_class.slice([1, 2, 3, 4, 5, 6], frame_length: 4, hop_length: 3, pad_end: true)

      expect(frames).to eq([[1, 2, 3, 4], [4, 5, 6, 0.0]])
    end

    it "validates frame and hop length" do
      expect do
        described_class.slice([1.0], frame_length: 0, hop_length: 1)
      end.to raise_error(Muze::ParameterError, /frame_length/)
    end
  end
end
