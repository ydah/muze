# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

module Muze
  module IO
    module AudioLoader
      # Generic audio backend implemented with ffmpeg/ffprobe CLI.
      module FFMPEGBackend
        module_function

        SUPPORTED_EXTENSIONS = %w[.flac .mp3 .ogg].freeze
        DEFAULT_TIMEOUT_SECONDS = 30
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
          @available = command_available?("ffmpeg") && command_available?("ffprobe") if @available.nil?
          @available
        end

        # @param extension [String]
        # @return [String]
        def installation_message(extension)
          format = extension.delete_prefix(".")
          "Unable to load #{format} because the FFmpeg backend is unavailable. #{INSTALLATION_STEPS.join(' ')}"
        end

        # @return [Boolean]
        def applies_time_window?
          true
        end

        # @param path [String]
        # @param offset [Float]
        # @param duration [Float, nil]
        # @return [Array(Array<Float>, Integer, Integer)]
        def read(path, offset: 0.0, duration: nil)
          raise Muze::DependencyError, installation_message(File.extname(path).downcase) unless available?

          source_sr, channels = probe_stream(path)
          [decode_samples(path, channels, offset:, duration:), source_sr, channels]
        end

        # @param path [String]
        # @return [Hash]
        def info(path)
          raise Muze::DependencyError, installation_message(File.extname(path).downcase) unless available?

          sample_rate, channels, duration = probe_stream(path, include_duration: true)
          {
            sample_rate: sample_rate,
            channels: channels,
            duration: duration,
            format: File.extname(path).delete_prefix(".")
          }
        end

        # @param path [String]
        # @return [Array(Integer, Integer)]
        def probe_stream(path, include_duration: false)
          stream_entries = include_duration ? "stream=sample_rate,channels,duration:format=duration" : "stream=sample_rate,channels"
          stdout, stderr, status = capture_with_timeout(
            "ffprobe",
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", stream_entries,
            "-of", "json",
            path
          )

          unless status.success?
            raise Muze::AudioLoadError, "ffprobe failed for #{path}: #{stderr.strip}"
          end

          parse_probe_output(stdout, path, stderr:, include_duration:)
        end
        private_class_method :probe_stream

        # @param raw_output [String]
        # @param path [String]
        # @param stderr [String]
        # @param include_duration [Boolean]
        # @return [Array(Integer, Integer, Float)]
        def parse_probe_output(raw_output, path, stderr:, include_duration:)
          data = JSON.parse(raw_output)
          stream = data.fetch("streams", []).first
          raise Muze::AudioLoadError, "No audio stream found in #{path}" unless stream

          source_sr = Integer(stream.fetch("sample_rate"))
          channels = Integer(stream.fetch("channels"))

          if source_sr <= 0 || channels <= 0
            raise Muze::AudioLoadError, "Invalid stream metadata for #{path}: sample_rate=#{source_sr}, channels=#{channels}"
          end

          return [source_sr, channels] unless include_duration

          duration = stream["duration"] || data.fetch("format", {})["duration"]
          [source_sr, channels, duration ? duration.to_f : nil]
        rescue JSON::ParserError, KeyError, TypeError, ArgumentError => e
          stderr_detail = stderr.to_s.strip
          suffix = stderr_detail.empty? ? "" : " stderr: #{stderr_detail}"
          raise Muze::AudioLoadError, "Failed to parse ffprobe output for #{path}: #{e.message}#{suffix}"
        end
        private_class_method :parse_probe_output

        # @param path [String]
        # @param channels [Integer]
        # @param offset [Float]
        # @param duration [Float, nil]
        # @return [Array<Float>, Array<Array<Float>>]
        def decode_samples(path, channels, offset:, duration:)
          floats, stderr, status = stream_float32le_with_timeout(
            "ffmpeg",
            "-v", "error",
            "-nostdin",
            *seek_args(offset),
            "-i", path,
            "-map", "0:a:0",
            "-vn",
            "-sn",
            *duration_args(duration),
            "-f", "f32le",
            "-acodec", "pcm_f32le",
            "pipe:1"
          )

          unless status.success?
            raise Muze::AudioLoadError, "ffmpeg failed for #{path}: #{stderr.strip}"
          end

          return floats if channels == 1

          unless (floats.length % channels).zero?
            raise Muze::AudioLoadError, "Decoded samples are not divisible by channels (#{floats.length} / #{channels})"
          end

          floats.each_slice(channels).map(&:dup)
        end
        private_class_method :decode_samples

        def seek_args(offset)
          offset.positive? ? ["-ss", offset.to_s] : []
        end
        private_class_method :seek_args

        def duration_args(duration)
          duration ? ["-t", duration.to_s] : []
        end
        private_class_method :duration_args

        def capture_with_timeout(*command)
          Timeout.timeout(DEFAULT_TIMEOUT_SECONDS) { Open3.capture3(*command) }
        rescue Timeout::Error
          raise Muze::AudioLoadError, "#{command.first} timed out after #{DEFAULT_TIMEOUT_SECONDS}s"
        end
        private_class_method :capture_with_timeout

        def stream_float32le_with_timeout(*command)
          floats = []
          stderr_data = +""
          status = nil
          wait_thread = nil
          reader_error = nil
          leftover = +"".b

          Timeout.timeout(DEFAULT_TIMEOUT_SECONDS) do
            Open3.popen3(*command) do |stdin, stdout, stderr, process_wait|
              wait_thread = process_wait
              stdin.close
              stdout.binmode
              reader = Thread.new do
                until stdout.eof?
                  data = leftover + stdout.readpartial(16 * 1024)
                  whole_bytes = data.bytesize - (data.bytesize % 4)
                  floats.concat(data.byteslice(0, whole_bytes).unpack("e*")) if whole_bytes.positive?
                  leftover = data.byteslice(whole_bytes, data.bytesize - whole_bytes) || +"".b
                end
              rescue EOFError
                nil
              rescue StandardError => e
                reader_error = e
              end
              stderr_reader = Thread.new { stderr_data << stderr.read.to_s }
              reader.join
              stderr_reader.join
              raise reader_error if reader_error
              raise Muze::AudioLoadError, "ffmpeg emitted a partial f32 sample" unless leftover.empty?

              status = process_wait.value
            end
          end
          [floats, stderr_data, status]
        rescue Timeout::Error
          terminate_process(wait_thread)
          raise Muze::AudioLoadError, "#{command.first} timed out after #{DEFAULT_TIMEOUT_SECONDS}s"
        end
        private_class_method :stream_float32le_with_timeout

        def terminate_process(wait_thread)
          return unless wait_thread&.pid

          Process.kill("TERM", wait_thread.pid)
          wait_thread.join(0.2)
          Process.kill("KILL", wait_thread.pid) if wait_thread.alive?
        rescue Errno::ESRCH
          nil
        end
        private_class_method :terminate_process

        # @param command [String]
        # @return [Boolean]
        def command_available?(command)
          Timeout.timeout(5) { system(command, "-version", out: File::NULL, err: File::NULL) }
        rescue Errno::ENOENT
          false
        rescue Timeout::Error
          false
        end
        private_class_method :command_available?
      end
    end
  end
end
