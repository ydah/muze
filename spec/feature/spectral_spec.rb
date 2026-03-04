# frozen_string_literal: true

RSpec.describe Muze::Feature do
  let(:sr) { 22_050 }

  def sine(freq, duration: 1.0)
    sample_count = (sr * duration).to_i
    Numo::SFloat.cast(
      Array.new(sample_count) { |index| Math.sin((2.0 * Math::PI * freq * index) / sr) }
    )
  end

  describe "spectral features" do
    it "estimates centroid around sine frequency" do
      centroid = described_class.spectral_centroid(y: sine(440.0), sr:, n_fft: 1024, hop_length: 256)
      mean_centroid = centroid.mean

      expect(mean_centroid).to be_within(80.0).of(440.0)
    end

    it "returns high flatness for white noise" do
      noise = Numo::SFloat.new(sr).rand(-1.0, 1.0)
      flatness = described_class.spectral_flatness(y: noise, n_fft: 1024, hop_length: 256)

      expect(flatness.mean).to be > 0.5
    end

    it "zero crossing rate increases with frequency" do
      low = described_class.zero_crossing_rate(sine(220.0), frame_length: 1024, hop_length: 256).mean
      high = described_class.zero_crossing_rate(sine(880.0), frame_length: 1024, hop_length: 256).mean

      expect(high).to be > low
    end

    it "returns RMS with frame dimension" do
      values = described_class.rms(y: sine(440.0), frame_length: 1024, hop_length: 256)

      expect(values.shape[0]).to eq(1)
      expect(values.shape[1]).to be > 0
    end
  end
end
