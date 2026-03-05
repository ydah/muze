# frozen_string_literal: true

require "fileutils"
require "open3"
require "tempfile"
require "tmpdir"

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

    it "loads wav/flac/mp3/ogg from the same source when ffmpeg is available" do
      skip "ffmpeg backend not available in this environment" unless Muze::IO::AudioLoader::FFMPEGBackend.available?

      Dir.mktmpdir("muze-audio-loader") do |tmpdir|
        source_wav = File.join(tmpdir, "source.wav")
        flac_path = File.join(tmpdir, "source.flac")
        mp3_path = File.join(tmpdir, "source.mp3")
        ogg_path = File.join(tmpdir, "source.ogg")

        FileUtils.cp(mono_path, source_wav)
        convert_with_ffmpeg(mono_path, flac_path)
        convert_with_ffmpeg(mono_path, mp3_path)
        convert_with_ffmpeg(mono_path, ogg_path)

        loaded = {
          wav: Muze.load(source_wav, sr: 44_100).first,
          flac: Muze.load(flac_path, sr: 44_100).first,
          mp3: Muze.load(mp3_path, sr: 44_100).first,
          ogg: Muze.load(ogg_path, sr: 44_100).first
        }

        baseline_size = loaded.fetch(:wav).size

        loaded.each do |format, signal|
          expect(signal).to be_a(Numo::SFloat)
          expect(signal.size).to be_within(64).of(baseline_size), "unexpected output length for #{format}"
        end
      end
    end

    it "includes installation steps when ffmpeg backend is unavailable" do
      allow(Muze::IO::AudioLoader::FFMPEGBackend).to receive(:available?).and_return(false)

      Tempfile.create(["muze-dummy", ".mp3"]) do |temp_file|
        expect do
          Muze.load(temp_file.path)
        end.to raise_error(
          Muze::AudioLoadError,
          /Install ffmpeg.*ffprobe.*brew install ffmpeg/
        )
      end
    end
  end

  def convert_with_ffmpeg(source_path, target_path)
    _stdout, stderr, status = Open3.capture3(
      "ffmpeg",
      "-y",
      "-loglevel",
      "error",
      "-i",
      source_path,
      target_path
    )

    return if status.success?

    raise "Failed to convert fixture with ffmpeg: #{stderr.strip}"
  end
end
