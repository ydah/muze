# frozen_string_literal: true

require "fileutils"
require "wavefile"

module SpecAudioGenerator
  module_function

  FIXTURE_DIR = File.expand_path("../fixtures", __dir__)

  def ensure_fixtures!
    FileUtils.mkdir_p(FIXTURE_DIR)
    generate_mono_sine(File.join(FIXTURE_DIR, "sine_440_mono_44100.wav"), sample_rate: 44_100, duration: 1.0)
    generate_stereo_sine(File.join(FIXTURE_DIR, "sine_440_stereo_44100.wav"), sample_rate: 44_100, duration: 1.0)
  end

  def generate_mono_sine(path, sample_rate:, duration:, frequency: 440.0, amplitude: 0.8)
    samples = sine_wave(sample_rate:, duration:, frequency:, amplitude:)
    write_wave(path, samples, channels: :mono, sample_rate:)
  end

  def generate_stereo_sine(path, sample_rate:, duration:, frequency: 440.0, amplitude: 0.8)
    left = sine_wave(sample_rate:, duration:, frequency:, amplitude:)
    right = sine_wave(sample_rate:, duration:, frequency: frequency * 2.0, amplitude: amplitude * 0.5)
    samples = left.zip(right)
    write_wave(path, samples, channels: :stereo, sample_rate:)
  end

  def sine_wave(sample_rate:, duration:, frequency:, amplitude:)
    sample_count = (sample_rate * duration).to_i
    Array.new(sample_count) do |index|
      angle = (2.0 * Math::PI * frequency * index) / sample_rate
      (amplitude * Math.sin(angle) * 32_767).round
    end
  end

  def write_wave(path, samples, channels:, sample_rate:)
    format = WaveFile::Format.new(channels, :pcm_16, sample_rate)
    WaveFile::Writer.new(path, format) do |writer|
      writer.write(WaveFile::Buffer.new(samples, format))
    end
  end
end
