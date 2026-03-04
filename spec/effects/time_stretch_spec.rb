# frozen_string_literal: true

RSpec.describe Muze::Effects do
  let(:sr) { 22_050 }
  let(:signal) do
    Numo::SFloat.cast(
      Array.new(sr) { |index| Math.sin((2.0 * Math::PI * 440.0 * index) / sr) }
    )
  end

  describe ".time_stretch" do
    it "changes output length by rate" do
      stretched = described_class.time_stretch(signal, rate: 2.0)

      expect(stretched.size).to be_within(1).of(signal.size / 2)
    end
  end

  describe ".pitch_shift" do
    it "keeps output length" do
      shifted = described_class.pitch_shift(signal, sr:, n_steps: 4)

      expect(shifted.size).to eq(signal.size)
    end
  end

  describe ".trim" do
    it "cuts leading and trailing silence" do
      padded = Numo::SFloat.zeros(signal.size + 4000)
      padded[2000...(2000 + signal.size)] = signal

      trimmed, (start_idx, end_idx) = described_class.trim(padded, top_db: 30)

      expect(trimmed.size).to be <= padded.size
      expect(start_idx).to be > 0
      expect(end_idx).to be > start_idx
    end
  end
end
