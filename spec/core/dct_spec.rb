# frozen_string_literal: true

RSpec.describe Muze::Core::DCT do
  describe ".dct" do
    it "computes DCT-II with orthonormal normalization" do
      input = Numo::SFloat[[1.0], [1.0], [1.0], [1.0]]
      result = described_class.dct(input, type: 2, norm: :ortho)

      expect(result[0, 0]).to be_within(1.0e-6).of(2.0)
      expect(result[1, 0].abs).to be < 1.0e-6
    end
  end
end
