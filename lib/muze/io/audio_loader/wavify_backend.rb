# frozen_string_literal: true

require "wavify/errors"
require "wavify/core/format"
require "wavify/core/duration"
require "wavify/core/sample_buffer"
require "wavify/codecs/base"
require "wavify/codecs/wav"

module Muze
  module IO
    module AudioLoader
      # WAV backend implemented with wavify's pure-Ruby WAV codec surface.
      module WavifyBackend
        module_function

        SUPPORTED_EXTENSIONS = %w[.wav .wave].freeze

        # @param extension [String]
        # @return [Boolean]
        def supported_extension?(extension)
          SUPPORTED_EXTENSIONS.include?(extension)
        end

        # @return [Boolean]
        def available?
          true
        end

        # @return [Boolean]
        def applies_time_window?
          true
        end

        # @param extension [String]
        # @return [String]
        def installation_message(extension)
          "Unable to load #{extension.delete_prefix('.')} because the WAV backend is unavailable."
        end

        # @param path [String]
        # @param offset [Float]
        # @param duration [Float, nil]
        # @return [Array(Array<Float>, Integer, Integer)]
        def read(path, offset: 0.0, duration: nil)
          metadata = Wavify::Codecs::Wav.metadata(path)
          source_format = metadata.fetch(:format)
          float_format = source_format.with(sample_format: :float, bit_depth: 32)
          samples = stream_samples(path, float_format:, offset:, duration:)

          [samples_from_interleaved(samples, float_format.channels), float_format.sample_rate, float_format.channels]
        end

        # @yieldparam samples [Array<Float>, Array<Array<Float>>]
        # @yieldparam sample_rate [Integer]
        # @yieldparam channels [Integer]
        # @return [void]
        def read_stream(path, chunk_frames:, offset: 0.0, duration: nil)
          metadata = Wavify::Codecs::Wav.metadata(path)
          source_format = metadata.fetch(:format)
          float_format = source_format.with(sample_format: :float, bit_depth: 32)

          stream_sample_chunks(path, float_format:, offset:, duration:, chunk_frames:) do |samples|
            yield samples_from_interleaved(samples, float_format.channels), float_format.sample_rate, float_format.channels
          end
        end

        # @param path [String]
        # @return [Hash]
        def info(path)
          metadata = Wavify::Codecs::Wav.metadata(path)
          format = metadata.fetch(:format)
          {
            sample_rate: format.sample_rate,
            channels: format.channels,
            duration: metadata.fetch(:duration).total_seconds,
            format: format_label(path)
          }
        end

        # @return [Array<Float>]
        def stream_samples(path, float_format:, offset:, duration:)
          start_frame = (offset * float_format.sample_rate).floor
          end_frame = duration ? start_frame + (duration * float_format.sample_rate).floor : nil
          samples = []
          current_frame = 0

          Wavify::Codecs::Wav.stream_read(path) do |chunk|
            converted = chunk.format == float_format ? chunk : chunk.convert(float_format)
            chunk_frames = converted.sample_frame_count
            chunk_start = current_frame
            chunk_end = current_frame + chunk_frames
            copy_start = [start_frame, chunk_start].max
            copy_end = end_frame ? [end_frame, chunk_end].min : chunk_end

            if copy_start < copy_end
              local_start = copy_start - chunk_start
              local_length = copy_end - copy_start
              samples.concat(converted.slice(local_start, local_length).samples)
            end

            current_frame = chunk_end
            break if end_frame && current_frame >= end_frame
          end

          samples
        end
        private_class_method :stream_samples

        def stream_sample_chunks(path, float_format:, offset:, duration:, chunk_frames:)
          start_frame = (offset * float_format.sample_rate).floor
          end_frame = duration ? start_frame + (duration * float_format.sample_rate).floor : nil
          current_frame = 0
          chunk_samples = [chunk_frames * float_format.channels, 1].max
          pending = []

          Wavify::Codecs::Wav.stream_read(path) do |chunk|
            converted = chunk.format == float_format ? chunk : chunk.convert(float_format)
            chunk_frames_count = converted.sample_frame_count
            chunk_start = current_frame
            chunk_end = current_frame + chunk_frames_count
            copy_start = [start_frame, chunk_start].max
            copy_end = end_frame ? [end_frame, chunk_end].min : chunk_end

            if copy_start < copy_end
              local_start = copy_start - chunk_start
              local_length = copy_end - copy_start
              pending.concat(converted.slice(local_start, local_length).samples)
              while pending.length >= chunk_samples
                yield pending.shift(chunk_samples)
              end
            end

            current_frame = chunk_end
            break if end_frame && current_frame >= end_frame
          end

          yield pending unless pending.empty?
        end
        private_class_method :stream_sample_chunks

        # @return [Array<Float>, Array<Array<Float>>]
        def samples_from_interleaved(samples, channels)
          return samples if channels == 1

          samples.each_slice(channels).map(&:dup)
        end
        private_class_method :samples_from_interleaved

        def format_label(source)
          return File.extname(source).delete_prefix(".") if source.is_a?(String)

          "wav"
        end
        private_class_method :format_label
      end
    end
  end
end
