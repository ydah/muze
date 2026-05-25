# frozen_string_literal: true

require "wavify/core/format"
require "wavify/core/sample_buffer"
require "wavify/codecs/base"
require "wavify/codecs/wav"

module Muze
  module IO
    # WAV writer for lightweight effects/analysis result inspection.
    module AudioWriter
      module_function

      def write(path, y, sr:, normalize: false, format: :wav)
        raise Muze::ParameterError, "sr must be positive" unless sr.is_a?(Integer) && sr.positive?
        format_label = format.to_s.downcase.to_sym
        raise Muze::UnsupportedFormatError, "only WAV output is supported" unless %i[wav wave].include?(format_label)

        signal = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
        signal = Muze::Core::Audio.normalize(signal) if normalize
        channels = signal.ndim == 2 ? signal.shape[1] : 1
        samples = flatten_samples(signal)
        sample_format = Wavify::Core::Format.new(channels:, sample_rate: sr, bit_depth: 32, sample_format: :float)
        buffer = Wavify::Core::SampleBuffer.new(samples, sample_format)
        Wavify::Codecs::Wav.write(output_target(path), buffer)
        path
      rescue Muze::Error
        raise
      rescue SystemCallError, Wavify::Error => e
        raise Muze::AudioLoadError, "Failed to write WAV output #{path}: #{e.message}"
      end

      def flatten_samples(signal)
        return signal.to_a if signal.ndim == 1

        signal.to_a.flat_map { |frame| frame.respond_to?(:to_a) ? frame.to_a : Array(frame) }
      end
      private_class_method :flatten_samples

      def output_target(path)
        path.respond_to?(:to_path) ? path.to_path : path
      end
      private_class_method :output_target
    end
  end
end
