# frozen_string_literal: true

RSpec.describe Muze::Core::Resample do
  describe ".resample" do
    it "changes sample length for target sr" do
      signal = Numo::SFloat.linspace(0.0, 1.0, 100)
      resampled = described_class.resample(signal, orig_sr: 100, target_sr: 50)

      expect(resampled.size).to eq(50)
    end
  end
end
