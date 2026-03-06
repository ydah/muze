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

        # @param path [String]
        # @return [Array(Array<Float>, Integer, Integer)]
        def read(path)
          buffer = Wavify::Codecs::Wav.read(path)
          float_format = buffer.format.with(sample_format: :float, bit_depth: 32)
          converted = buffer.convert(float_format)

          samples = samples_from_buffer(converted)
          [samples, converted.format.sample_rate, converted.format.channels]
        end

        # @param buffer [Wavify::Core::SampleBuffer]
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
