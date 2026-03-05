# frozen_string_literal: true

require "wavify"

module Muze
  module IO
    module AudioLoader
      # WAV backend implemented with wavify.
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

        # @param path [String]
        # @return [Array(Array<Float>, Integer, Integer)]
        def read(path)
          audio = Wavify::Audio.read(path)
          float_format = audio.format.with(sample_format: :float, bit_depth: 32)
          converted = audio.convert(float_format)

          samples = samples_from_buffer(converted.buffer)
          [samples, converted.format.sample_rate, converted.format.channels]
        end

        # @param buffer [Wavify::Buffer]
        # @return [Array<Float>, Array<Array<Float>>]
        def samples_from_buffer(buffer)
          return buffer.samples if buffer.format.channels == 1

          buffer.samples.each_slice(buffer.format.channels).map(&:dup)
        end
        private_class_method :samples_from_buffer
      end
    end
  end
end
