# frozen_string_literal: true

module Muze
  module Core
    # Window function generators for short-time analysis.
    module Windows
      module_function

      # @param n [Integer]
      # @return [Numo::SFloat]
      def hann(n)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n) { |k, denom| 0.5 * (1.0 - Math.cos((2.0 * Math::PI * k) / denom)) }
      end

      # @param n [Integer]
      # @return [Numo::SFloat]
      def hamming(n)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n) { |k, denom| 0.54 - (0.46 * Math.cos((2.0 * Math::PI * k) / denom)) }
      end

      # @param n [Integer]
      # @return [Numo::SFloat]
      def blackman(n)
        raise Muze::ParameterError, "window length must be positive" if n <= 0
        return Numo::SFloat[1.0] if n == 1

        build_window(n) do |k, denom|
          phase = (2.0 * Math::PI * k) / denom
          0.42 - (0.5 * Math.cos(phase)) + (0.08 * Math.cos(2.0 * phase))
        end
      end

      # @param n [Integer]
      # @return [Numo::SFloat]
      def ones(n)
        raise Muze::ParameterError, "window length must be positive" if n <= 0

        Numo::SFloat.ones(n)
      end

      # @param name [Symbol]
      # @param n [Integer]
      # @return [Numo::SFloat]
      def resolve(name, n)
        case name
        when :hann then hann(n)
        when :hamming then hamming(n)
        when :blackman then blackman(n)
        when :ones, :boxcar, :rect then ones(n)
        else
          raise Muze::ParameterError, "Unsupported window: #{name}"
        end
      end

      def build_window(length)
        denominator = length - 1
        values = Array.new(length) { |k| yield(k, denominator).to_f }
        Numo::SFloat.cast(values)
      end
      private_class_method :build_window
    end
  end
end
