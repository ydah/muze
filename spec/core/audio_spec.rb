# frozen_string_literal: true

RSpec.describe Muze::Core::Audio do
  describe ".valid_audio?" do
    it "accepts finite mono and stereo audio" do
      expect(Muze.valid_audio?([0.0, 1.0])).to be(true)
      expect(Muze.valid_audio?(Numo::SFloat.cast([[0.0, 1.0], [0.5, -0.5]]))).to be(true)
    end

    it "rejects nil, empty, and non-finite audio" do
      expect(Muze.valid_audio?(nil)).to be(false)
      expect(Muze.valid_audio?([])).to be(false)
      expect(Muze.valid_audio?([Float::NAN])).to be(false)
    end
  end

  describe ".normalize" do
    it "scales audio to a target peak" do
      normalized = Muze.normalize([0.0, 2.0, -1.0], peak: 0.5)

      expect(normalized.abs.max).to be_within(1.0e-6).of(0.5)
    end

    it "can normalize channels independently" do
      stereo = Numo::SFloat.cast([[0.0, 0.0], [2.0, 0.5]])
      normalized = Muze.normalize(stereo, axis: :channels)

      expect(normalized[true, 0].abs.max).to be_within(1.0e-6).of(1.0)
      expect(normalized[true, 1].abs.max).to be_within(1.0e-6).of(1.0)
    end
  end

  describe ".remix" do
    it "concatenates sample intervals" do
      remixed = Muze.remix([0, 1, 2, 3, 4, 5], [[1, 3], [4, 6]])

      expect(remixed.to_a).to eq([1.0, 2.0, 4.0, 5.0])
    end

    it "supports time intervals for multi-channel audio" do
      stereo = Numo::SFloat.cast([[0, 10], [1, 11], [2, 12], [3, 13]])
      remixed = Muze.remix(stereo, [[0.0, 0.02]], units: :time, sr: 100)

      expect(remixed.shape).to eq([2, 2])
      expect(remixed[true, 0].to_a).to eq([0.0, 1.0])
    end
  end
end
