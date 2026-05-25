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
          buffer = Wavify::Codecs::Wav.read(path)
          float_format = buffer.format.with(sample_format: :float, bit_depth: 32)
          converted = buffer.convert(float_format)

          samples = samples_from_buffer(converted, offset:, duration:)
          [samples, converted.format.sample_rate, converted.format.channels]
        end

        # @param path [String]
        # @return [Hash]
        def info(path)
          buffer = Wavify::Codecs::Wav.read(path)
          {
            sample_rate: buffer.format.sample_rate,
            channels: buffer.format.channels,
            duration: buffer.duration.total_seconds,
            format: format_label(path)
          }
        end

        # @param buffer [Wavify::Core::SampleBuffer]
        # @return [Array<Float>, Array<Array<Float>>]
        def samples_from_buffer(buffer, offset:, duration:)
          channels = buffer.format.channels
          start_frame = (offset * buffer.format.sample_rate).floor
          frame_count = duration ? (duration * buffer.format.sample_rate).floor : buffer.sample_frame_count - start_frame
          start_sample = start_frame * channels
          sample_count = [frame_count, 0].max * channels
          samples = buffer.samples[start_sample, sample_count] || []
          return samples if channels == 1

          samples.each_slice(channels).map(&:dup)
        end
        private_class_method :samples_from_buffer

        def format_label(source)
          return File.extname(source).delete_prefix(".") if source.is_a?(String)

          "wav"
        end
        private_class_method :format_label
      end
    end
  end
end
