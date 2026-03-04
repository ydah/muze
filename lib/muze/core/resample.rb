# frozen_string_literal: true

module Muze
  module Core
    # Resampling utilities.
    module Resample
      EPSILON = 1.0e-12
      module_function

      # @param y [Numo::SFloat, Array<Float>] waveform signal
      # @param orig_sr [Integer] source sampling rate
      # @param target_sr [Integer] destination sampling rate
      # @param res_type [Symbol] :linear or :sinc
      # @return [Numo::SFloat] resampled waveform
      def resample(y, orig_sr:, target_sr:, res_type: :sinc)
        validate_sample_rates!(orig_sr, target_sr)
        signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
        return Numo::SFloat.cast(signal) if signal.empty? || orig_sr == target_sr

        case res_type
        when :linear then linear_resample(signal, orig_sr, target_sr)
        when :sinc then sinc_resample(signal, orig_sr, target_sr)
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

      def sinc_resample(signal, orig_sr, target_sr)
        ratio = target_sr.to_f / orig_sr
        target_length = [(signal.length * ratio).round, 1].max
        taps = 16
        beta = 8.6
        cutoff = [ratio, 1.0].min

        i0_beta = bessel_i0(beta)
        output = Array.new(target_length, 0.0)

        target_length.times do |index|
          source_position = index / ratio
          left = source_position.floor - taps + 1
          right = source_position.floor + taps

          sum = 0.0
          weight_sum = 0.0

          (left..right).each do |sample_index|
            next if sample_index.negative? || sample_index >= signal.length

            distance = source_position - sample_index
            normalized = distance / taps.to_f
            next if normalized.abs > 1.0

            window = bessel_i0(beta * Math.sqrt(1.0 - (normalized * normalized))) / i0_beta
            weight = cutoff * sinc(cutoff * distance) * window
            sum += signal[sample_index] * weight
            weight_sum += weight
          end

          output[index] = weight_sum.abs > EPSILON ? (sum / weight_sum) : 0.0
        end

        Numo::SFloat.cast(output)
      end
      private_class_method :sinc_resample

      def sinc(value)
        return 1.0 if value.abs < EPSILON

        x = Math::PI * value
        Math.sin(x) / x
      end
      private_class_method :sinc

      # Approximation of modified Bessel function I0.
      def bessel_i0(value)
        sum = 1.0
        term = 1.0
        k = 1

        loop do
          term *= ((value / 2.0)**2) / (k * k)
          sum += term
          break if term < 1.0e-12

          k += 1
        end

        sum
      end
      private_class_method :bessel_i0
    end
  end
end
