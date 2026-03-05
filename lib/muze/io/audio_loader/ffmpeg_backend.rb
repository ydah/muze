# frozen_string_literal: true

require "json"
require "open3"

module Muze
  module IO
    module AudioLoader
      # Generic audio backend implemented with ffmpeg/ffprobe CLI.
      module FFMPEGBackend
        module_function

        SUPPORTED_EXTENSIONS = %w[.flac .mp3 .ogg].freeze
        INSTALLATION_STEPS = [
          "Install ffmpeg and ensure both `ffmpeg` and `ffprobe` are available on PATH.",
          "macOS: `brew install ffmpeg`.",
          "Ubuntu/Debian: `sudo apt-get install ffmpeg`."
        ].freeze

        # @param extension [String]
        # @return [Boolean]
        def supported_extension?(extension)
          SUPPORTED_EXTENSIONS.include?(extension)
        end

        # @return [Boolean]
        def available?
          command_available?("ffmpeg") && command_available?("ffprobe")
        end

        # @param extension [String]
        # @return [String]
        def installation_message(extension)
          format = extension.delete_prefix(".")
          "Unable to load #{format} because the FFmpeg backend is unavailable. #{INSTALLATION_STEPS.join(' ')}"
        end

        # @param path [String]
        # @return [Array(Array<Float>, Integer, Integer)]
        def read(path)
          raise Muze::DependencyError, installation_message(File.extname(path).downcase) unless available?

          source_sr, channels = probe_stream(path)
          [decode_samples(path, channels), source_sr, channels]
        end

        # @param path [String]
        # @return [Array(Integer, Integer)]
        def probe_stream(path)
          stdout, stderr, status = Open3.capture3(
            "ffprobe",
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels",
            "-of", "json",
            path
          )

          unless status.success?
            raise Muze::AudioLoadError, "ffprobe failed for #{path}: #{stderr.strip}"
          end

          parse_probe_output(stdout, path)
        end
        private_class_method :probe_stream

        # @param raw_output [String]
        # @param path [String]
        # @return [Array(Integer, Integer)]
        def parse_probe_output(raw_output, path)
          data = JSON.parse(raw_output)
          stream = data.fetch("streams", []).first
          raise Muze::AudioLoadError, "No audio stream found in #{path}" unless stream

          source_sr = Integer(stream.fetch("sample_rate"))
          channels = Integer(stream.fetch("channels"))

          if source_sr <= 0 || channels <= 0
            raise Muze::AudioLoadError, "Invalid stream metadata for #{path}: sample_rate=#{source_sr}, channels=#{channels}"
          end

          [source_sr, channels]
        rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
          raise Muze::AudioLoadError, "Failed to parse ffprobe output for #{path}: #{e.message}"
        end
        private_class_method :parse_probe_output

        # @param path [String]
        # @param channels [Integer]
        # @return [Array<Float>, Array<Array<Float>>]
        def decode_samples(path, channels)
          raw_samples, stderr, status = Open3.capture3(
            "ffmpeg",
            "-v", "error",
            "-i", path,
            "-f", "f32le",
            "-acodec", "pcm_f32le",
            "pipe:1"
          )

          unless status.success?
            raise Muze::AudioLoadError, "ffmpeg failed for #{path}: #{stderr.strip}"
          end

          floats = raw_samples.unpack("e*")
          return floats if channels == 1

          unless (floats.length % channels).zero?
            raise Muze::AudioLoadError, "Decoded samples are not divisible by channels (#{floats.length} / #{channels})"
          end

          floats.each_slice(channels).map(&:dup)
        end
        private_class_method :decode_samples

        # @param command [String]
        # @return [Boolean]
        def command_available?(command)
          system(command, "-version", out: File::NULL, err: File::NULL)
        rescue Errno::ENOENT
          false
        end
        private_class_method :command_available?
      end
    end
  end
end
