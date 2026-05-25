# frozen_string_literal: true

RSpec.describe Muze::Core::Resample do
  describe ".resample" do
    it "changes sample length for target sr" do
      signal = Numo::SFloat.linspace(0.0, 1.0, 100)
      resampled = described_class.resample(signal, orig_sr: 100, target_sr: 50)

      expect(resampled.size).to eq(50)
    end

    it "resamples multi-channel input directly" do
      signal = Numo::SFloat.cast([[0.0, 1.0], [0.5, 0.5], [1.0, 0.0]])
      result = described_class.resample(signal, orig_sr: 3, target_sr: 6, res_type: :linear)

      expect(result.shape).to eq([6, 2])
    end

    it "supports nearest and target_length" do
      signal = Numo::SFloat[0.0, 1.0, 0.0]
      result = described_class.resample(signal, orig_sr: 3, target_sr: 9, res_type: :nearest, target_length: 5)

      expect(result.size).to eq(5)
      expect(result.to_a).to all(satisfy { |value| [0.0, 1.0].include?(value) })
    end

    it "supports polyphase resampling" do
      signal = Numo::SFloat.cast(Array.new(120) { |index| Math.sin((2.0 * Math::PI * index) / 24.0) })
      result = described_class.resample(signal, orig_sr: 12_000, target_sr: 8_000, res_type: :polyphase)

      expect(result.size).to eq(80)
      expect(result.to_a.all?(&:finite?)).to be(true)
    end

    it "rejects non-finite audio input" do
      expect do
        described_class.resample([0.0, Float::NAN], orig_sr: 100, target_sr: 50)
      end.to raise_error(Muze::ParameterError, /finite/)
    end
  end
end
