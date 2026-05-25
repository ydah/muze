# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require "stringio"
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

    it "preserves source sample rate when sr is nil" do
      y, sr = Muze.load(mono_path, sr: nil)

      expect(sr).to eq(44_100)
      expect(y.size).to eq(44_100)
    end

    it "supports offset and duration" do
      y, _ = Muze.load(mono_path, sr: 44_100, offset: 0.25, duration: 0.5)

      expect(y.size).to be_within(1).of(22_050)
    end

    it "accepts Pathname input" do
      y, sr = Muze.load(Pathname(mono_path), sr: 44_100)

      expect(sr).to eq(44_100)
      expect(y.size).to eq(44_100)
    end

    it "can return stereo channels without downmixing" do
      y, _ = Muze.load(stereo_path, sr: 44_100, mono: false)

      expect(y.shape).to eq([44_100, 2])
    end

    it "supports explicit left and right mono selection" do
      left, = Muze.load(stereo_path, sr: 44_100, mono: :left)
      right, = Muze.load(stereo_path, sr: 44_100, mono: :right)

      expect(left.ndim).to eq(1)
      expect(right.ndim).to eq(1)
      expect(left.size).to eq(right.size)
    end

    it "supports weighted stereo downmix" do
      left, = Muze.load(stereo_path, sr: 44_100, mono: :left)
      weighted, = Muze.load(stereo_path, sr: 44_100, mono: :weighted, weights: [1.0, 0.0])

      expect((left - weighted).abs.max).to be < 1.0e-6
    end

    it "loads WAV data from StringIO with explicit format" do
      io = StringIO.new(File.binread(mono_path))
      y, sr = Muze.load(io, sr: 44_100, format: :wav)

      expect(sr).to eq(44_100)
      expect(y.size).to eq(44_100)
    end

    it "applies offset and duration to WAV StringIO input" do
      io = StringIO.new(File.binread(mono_path))
      y, sr = Muze.load(io, sr: 44_100, format: :wav, offset: 0.5, duration: 0.25)

      expect(sr).to eq(44_100)
      expect(y.size).to be_within(1).of(11_025)
    end

    it "rejects files larger than max_bytes" do
      expect do
        Muze.load(mono_path, max_bytes: 1)
      end.to raise_error(Muze::AudioLoadError, /too large/)
    end

    it "supports dtype and peak normalization" do
      y, = Muze.load(mono_path, sr: 44_100, dtype: :dfloat, normalize: true)

      expect(y).to be_a(Numo::DFloat)
      expect(y.abs.max).to be_within(1.0e-6).of(1.0)
    end

    it "reports audio metadata without loading through the public API" do
      info = Muze.info(mono_path)

      expect(info).to include(sample_rate: 44_100, channels: 1, format: "wav")
      expect(info.fetch(:duration)).to be_within(1.0e-6).of(1.0)
    end

    it "lists .wave among supported formats" do
      expect(described_class::SUPPORTED_FORMATS).to include("wave")
    end

    it "raises ParameterError for invalid arguments" do
      expect do
        Muze.load(mono_path, sr: 0)
      end.to raise_error(Muze::ParameterError, /sr/)
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

RSpec.describe Muze::IO::AudioWriter do
  describe ".write" do
    it "writes mono WAV output that can be loaded again" do
      Dir.mktmpdir("muze-audio-writer") do |tmpdir|
        path = File.join(tmpdir, "output.wav")
        signal = Numo::SFloat.cast([0.0, 0.5, -0.5, 0.0])

        Muze.write(path, signal, sr: 8_000)
        loaded, sr = Muze.load(path, sr: 8_000)

        expect(sr).to eq(8_000)
        expect(loaded.size).to eq(signal.size)
        expect((loaded - signal).abs.max).to be < 1.0e-6
      end
    end

    it "writes stereo WAV output and supports normalization" do
      Dir.mktmpdir("muze-audio-writer") do |tmpdir|
        path = Pathname(File.join(tmpdir, "stereo.wav"))
        signal = Numo::SFloat.cast([[0.0, 0.0], [2.0, -1.0]])

        Muze.write(path, signal, sr: 8_000, normalize: true)
        loaded, = Muze.load(path, sr: 8_000, mono: false)

        expect(loaded.shape).to eq(signal.shape)
        expect(loaded.abs.max).to be_within(1.0e-6).of(1.0)
      end
    end

    it "rejects unsupported output formats" do
      expect do
        Muze.write("out.flac", [0.0], sr: 8_000, format: :flac)
      end.to raise_error(Muze::UnsupportedFormatError, /WAV/)
    end

    it "rejects non-boolean normalization" do
      expect do
        Muze.write("out.wav", [0.0], sr: 8_000, normalize: :yes)
      end.to raise_error(Muze::ParameterError, /normalize/)
    end
  end
end
