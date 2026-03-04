# frozen_string_literal: true

RSpec.describe Muze::IO::AudioLoader do
  let(:mono_path) { File.expand_path("../fixtures/sine_440_mono_44100.wav", __dir__) }
  let(:stereo_path) { File.expand_path("../fixtures/sine_440_stereo_44100.wav", __dir__) }

  describe ".load" do
    it "loads mono wav and normalizes into Numo::SFloat" do
      y, sr = Muze.load(mono_path, sr: 44_100)

      expect(sr).to eq(44_100)
      expect(y).to be_a(Numo::SFloat)
      expect(y.size).to eq(44_100)
      expect(y.abs.max).to be <= 1.0
    end

    it "mixes stereo down to mono" do
      y, _ = Muze.load(stereo_path, sr: 44_100, mono: true)

      expect(y.ndim).to eq(1)
      expect(y.size).to eq(44_100)
    end

    it "resamples when target sampling rate is different" do
      y, sr = Muze.load(mono_path, sr: 22_050)

      expect(sr).to eq(22_050)
      expect(y.size).to be_within(1).of(22_050)
    end

    it "supports offset and duration" do
      y, _ = Muze.load(mono_path, sr: 44_100, offset: 0.25, duration: 0.5)

      expect(y.size).to be_within(1).of(22_050)
    end

    it "raises AudioLoadError for missing file" do
      expect do
        Muze.load("spec/fixtures/not_found.wav")
      end.to raise_error(Muze::AudioLoadError)
    end
  end
end
