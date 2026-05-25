# frozen_string_literal: true

module Muze
  module Core
    # Window function generators for short-time analysis.
    module Windows
      CACHE = {}
      module_function

      # @param n [Integer]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def hann(n, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n, periodic:) { |k, denom| 0.5 * (1.0 - Math.cos((2.0 * Math::PI * k) / denom)) }
      end

      # @param n [Integer]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def hamming(n, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n, periodic:) { |k, denom| 0.54 - (0.46 * Math.cos((2.0 * Math::PI * k) / denom)) }
      end

      # @param n [Integer]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def blackman(n, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n, periodic:) do |k, denom|
          phase = (2.0 * Math::PI * k) / denom
          0.42 - (0.5 * Math.cos(phase)) + (0.08 * Math.cos(2.0 * phase))
        end
      end

      # @param n [Integer]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def blackman_harris(n, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n, periodic:) do |k, denom|
          phase = (2.0 * Math::PI * k) / denom
          0.35875 - (0.48829 * Math.cos(phase)) + (0.14128 * Math.cos(2.0 * phase)) - (0.01168 * Math.cos(3.0 * phase))
        end
      end

      # @param n [Integer]
      # @param beta [Float]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def kaiser(n, beta: 14.0, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        denominator = bessel_i0(beta)
        build_window(n, periodic:) do |k, denom|
          ratio = ((2.0 * k) / denom) - 1.0
          bessel_i0(beta * Math.sqrt([1.0 - (ratio * ratio), 0.0].max)) / denominator
        end
      end

      # @param n [Integer]
      # @param alpha [Float]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def tukey(n, alpha: 0.5, periodic: false)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        raise Muze::ParameterError, "alpha must be between 0 and 1" unless alpha.between?(0.0, 1.0)
        return ones(n) if alpha.zero?
        return hann(n, periodic:) if alpha == 1.0
        return Numo::SFloat[1.0] if n == 1

        build_window(n, periodic:) do |k, denom|
          position = k.to_f / denom
          if position < alpha / 2.0
            0.5 * (1.0 + Math.cos(Math::PI * ((2.0 * position / alpha) - 1.0)))
          elsif position <= 1.0 - (alpha / 2.0)
            1.0
          else
            0.5 * (1.0 + Math.cos(Math::PI * ((2.0 * position / alpha) - (2.0 / alpha) + 1.0)))
          end
        end
      end

      # @param n [Integer]
      # @return [Numo::SFloat]
      def ones(n)
        raise Muze::ParameterError, "window length must be positive" if n <= 0

        Numo::SFloat.ones(n)
      end

      # @param name [Symbol, Array, Numo::NArray, Proc]
      # @param n [Integer]
      # @param periodic [Boolean]
      # @return [Numo::SFloat]
      def resolve(name, n, periodic: false)
        resolved = case name
                   when Numo::NArray then Numo::SFloat.cast(name)
                   when Array then Numo::SFloat.cast(name)
                   when Proc then Numo::SFloat.cast(name.call(n))
                   when Symbol then cached_symbol_window(name, n, periodic:)
                   else
                     raise Muze::ParameterError, "Unsupported window: #{name.inspect}"
                   end

        raise Muze::ParameterError, "window must have length #{n}" unless resolved.size == n

        resolved
      end

      def cached_symbol_window(name, n, periodic:)
        key = [name, n, periodic]
        CACHE[key] ||= case name
                       when :hann then hann(n, periodic:)
                       when :hamming then hamming(n, periodic:)
                       when :blackman then blackman(n, periodic:)
                       when :blackman_harris, :blackmanharris then blackman_harris(n, periodic:)
                       when :kaiser then kaiser(n, periodic:)
                       when :tukey then tukey(n, periodic:)
                       when :ones, :boxcar, :rect then ones(n)
                       else
                         raise Muze::ParameterError, "Unsupported window: #{name}"
                       end
      end
      private_class_method :cached_symbol_window

      def build_window(length, periodic:)
        denominator = periodic ? length : length - 1
        values = Array.new(length) { |k| yield(k, denominator).to_f }
        Numo::SFloat.cast(values)
      end
      private_class_method :build_window

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
