# frozen_string_literal: true

RSpec.describe Muze::Core::Resample do
  def sine(sr, freq, duration)
    count = (sr * duration).to_i
    Numo::SFloat.cast(Array.new(count) { |idx| Math.sin((2.0 * Math::PI * freq * idx) / sr) })
  end

  describe "sinc resampling" do
    it "preserves low frequency content on downsample" do
      original = sine(44_100, 1000.0, 1.0)
      down = described_class.resample(original, orig_sr: 44_100, target_sr: 22_050, res_type: :sinc)
      expected = sine(22_050, 1000.0, 1.0)

      dot = (down * expected).sum
      norm = Math.sqrt((down**2).sum * (expected**2).sum)
      correlation = dot / norm

      expect(correlation).to be > 0.98
    end

    it "keeps signal close after up/down roundtrip" do
      original = sine(22_050, 440.0, 1.0)
      up = described_class.resample(original, orig_sr: 22_050, target_sr: 44_100, res_type: :sinc)
      down = described_class.resample(up, orig_sr: 44_100, target_sr: 22_050, res_type: :sinc)

      restored = down[0...original.size]
      error = (restored - original).abs.mean
      expect(error).to be < 0.02
    end
  end
end
