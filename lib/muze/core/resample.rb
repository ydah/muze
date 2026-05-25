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
      # @param res_type [Symbol] :nearest, :linear, :sinc, or :polyphase
      # @param target_length [Integer, nil]
      # @param taps [Integer]
      # @param beta [Float]
      # @param cutoff [Float, nil]
      # @return [Numo::SFloat] resampled waveform
      def resample(y, orig_sr:, target_sr:, res_type: :sinc, target_length: nil, taps: 16, beta: 8.6, cutoff: nil)
        validate_sample_rates!(orig_sr, target_sr)
        validate_resample_options!(target_length:, taps:, beta:, cutoff:)

        signal = Numo::SFloat.cast(y)
        return signal if signal.empty?

        if signal.ndim == 2
          return resample_channels(signal, orig_sr:, target_sr:, res_type:, target_length:, taps:, beta:, cutoff:)
        end

        source = signal.to_a
        return adjust_length(source, target_length) if orig_sr == target_sr && target_length
        return signal if orig_sr == target_sr

        case res_type
        when :nearest then nearest_resample(source, orig_sr, target_sr, target_length:)
        when :linear then linear_resample(source, orig_sr, target_sr, target_length:)
        when :sinc then sinc_resample(source, orig_sr, target_sr, target_length:, taps:, beta:, cutoff:)
        when :polyphase then polyphase_resample(source, orig_sr, target_sr, target_length:, taps:, beta:, cutoff:)
        else
          raise Muze::ParameterError, "Unsupported res_type: #{res_type}"
        end
      end

      def validate_sample_rates!(orig_sr, target_sr)
        return if orig_sr.is_a?(Integer) && target_sr.is_a?(Integer) && orig_sr.positive? && target_sr.positive?

        raise Muze::ParameterError, "orig_sr and target_sr must be positive integers"
      end
      private_class_method :validate_sample_rates!

      def validate_resample_options!(target_length:, taps:, beta:, cutoff:)
        raise Muze::ParameterError, "target_length must be positive" if target_length && (!target_length.is_a?(Integer) || target_length <= 0)
        raise Muze::ParameterError, "taps must be positive" unless taps.is_a?(Integer) && taps.positive?
        raise Muze::ParameterError, "beta must be finite and non-negative" unless beta.respond_to?(:finite?) && beta.finite? && !beta.negative?
        return if cutoff.nil? || (cutoff.respond_to?(:finite?) && cutoff.finite? && cutoff.positive? && cutoff <= 1.0)

        raise Muze::ParameterError, "cutoff must be > 0 and <= 1"
      end
      private_class_method :validate_resample_options!

      def resample_channels(signal, orig_sr:, target_sr:, res_type:, target_length:, taps:, beta:, cutoff:)
        frames, channels = signal.shape
        return signal if frames.zero? || channels.zero?

        resampled_channels = channels.times.map do |channel_index|
          resample(
            signal[true, channel_index],
            orig_sr:,
            target_sr:,
            res_type:,
            target_length:,
            taps:,
            beta:,
            cutoff:
          ).to_a
        end

        output_length = resampled_channels.first.length
        output = Numo::SFloat.zeros(output_length, channels)
        channels.times do |channel_index|
          output[true, channel_index] = Numo::SFloat.cast(resampled_channels[channel_index])
        end
        output
      end
      private_class_method :resample_channels

      def output_length(source_length, orig_sr, target_sr, target_length:)
        target_length || [(source_length * target_sr.to_f / orig_sr).round, 1].max
      end
      private_class_method :output_length

      def nearest_resample(signal, orig_sr, target_sr, target_length:)
        source_length = signal.length
        return Numo::SFloat.cast(signal) if source_length <= 1

        target_size = output_length(source_length, orig_sr, target_sr, target_length:)
        scale = source_length.to_f / target_size
        output = Array.new(target_size) do |index|
          source_index = [(index * scale).round, source_length - 1].min
          signal[source_index]
        end

        Numo::SFloat.cast(output)
      end
      private_class_method :nearest_resample

      def linear_resample(signal, orig_sr, target_sr, target_length:)
        source_length = signal.length
        return Numo::SFloat.cast(signal) if source_length <= 1

        target_size = output_length(source_length, orig_sr, target_sr, target_length:)
        return Numo::SFloat.cast(signal[0, target_size]) if target_size <= 1

        scale = (source_length - 1).to_f / (target_size - 1)
        output = Array.new(target_size, 0.0)

        target_size.times do |index|
          source_position = index * scale
          left = source_position.floor
          right = [left + 1, source_length - 1].min
          alpha = source_position - left
          output[index] = ((1.0 - alpha) * signal[left]) + (alpha * signal[right])
        end

        Numo::SFloat.cast(output)
      end
      private_class_method :linear_resample

      def sinc_resample(signal, orig_sr, target_sr, target_length:, taps:, beta:, cutoff:)
        ratio = target_sr.to_f / orig_sr
        target_size = output_length(signal.length, orig_sr, target_sr, target_length:)
        cutoff ||= [ratio, 1.0].min

        i0_beta = bessel_i0(beta)
        output = Array.new(target_size, 0.0)

        target_size.times do |index|
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

      def polyphase_resample(signal, orig_sr, target_sr, target_length:, taps:, beta:, cutoff:)
        divisor = orig_sr.gcd(target_sr)
        up = target_sr / divisor
        down = orig_sr / divisor
        return sinc_resample(signal, orig_sr, target_sr, target_length:, taps:, beta:, cutoff:) if up > 32 || down > 32

        expanded = Array.new(signal.length * up, 0.0)
        signal.each_with_index { |sample, index| expanded[index * up] = sample }
        filtered = sinc_resample(expanded, orig_sr * up, orig_sr * up, target_length: expanded.length, taps:, beta:, cutoff: cutoff || (1.0 / [up, down].max))
        decimated = filtered.to_a.each_slice(down).map(&:first)
        adjust_length(decimated, target_length || output_length(signal.length, orig_sr, target_sr, target_length:))
      end
      private_class_method :polyphase_resample

      def adjust_length(signal, target_length)
        return Numo::SFloat.cast(signal) unless target_length
        return Numo::SFloat.cast(signal[0, target_length]) if signal.length >= target_length

        Numo::SFloat.cast(signal + Array.new(target_length - signal.length, 0.0))
      end
      private_class_method :adjust_length

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
