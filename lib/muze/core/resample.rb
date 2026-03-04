# frozen_string_literal: true

module Muze
  module Core
    # Resampling utilities.
    module Resample
      module_function

      # @param y [Numo::SFloat, Array<Float>] waveform signal
      # @param orig_sr [Integer] source sampling rate
      # @param target_sr [Integer] destination sampling rate
      # @param res_type [Symbol] :linear or :sinc
      # @return [Numo::SFloat] resampled waveform
      def resample(y, orig_sr:, target_sr:, res_type: :linear)
        validate_sample_rates!(orig_sr, target_sr)
        signal = y.is_a?(Numo::NArray) ? y.to_a : y
        return Numo::SFloat.cast(signal) if signal.empty? || orig_sr == target_sr

        case res_type
        when :linear then linear_resample(signal, orig_sr, target_sr)
        when :sinc then linear_resample(signal, orig_sr, target_sr)
        else
          raise Muze::ParameterError, "Unsupported res_type: #{res_type}"
        end
      end

      def validate_sample_rates!(orig_sr, target_sr)
        return if orig_sr.is_a?(Integer) && target_sr.is_a?(Integer) && orig_sr.positive? && target_sr.positive?

        raise Muze::ParameterError, "orig_sr and target_sr must be positive integers"
      end
      private_class_method :validate_sample_rates!

      def linear_resample(signal, orig_sr, target_sr)
        source_length = signal.length
        return Numo::SFloat.cast(signal) if source_length <= 1

        target_length = [(source_length * target_sr.to_f / orig_sr).round, 1].max
        return Numo::SFloat.cast(signal[0, target_length]) if target_length <= 1

        scale = (source_length - 1).to_f / (target_length - 1)
        output = Array.new(target_length, 0.0)

        target_length.times do |index|
          source_position = index * scale
          left = source_position.floor
          right = [left + 1, source_length - 1].min
          alpha = source_position - left
          output[index] = ((1.0 - alpha) * signal[left]) + (alpha * signal[right])
        end

        Numo::SFloat.cast(output)
      end
      private_class_method :linear_resample
    end
  end
end
