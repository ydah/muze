# frozen_string_literal: true

module Muze
  module Core
    # DCT utilities.
    module DCT
      module_function

      # @param x [Numo::NArray]
      # @param type [Integer]
      # @param n [Integer, nil]
      # @param axis [Integer]
      # @param norm [Symbol, nil]
      # @return [Numo::SFloat]
      def dct(x, type: 2, n: nil, axis: 0, norm: :ortho)
        raise Muze::ParameterError, "only DCT type 2 is supported" unless type == 2
        raise Muze::ParameterError, "axis must be 0 or 1" unless [0, 1].include?(axis)

        matrix = Numo::SFloat.cast(x)
        matrix = matrix.expand_dims(1) if matrix.ndim == 1
        matrix = matrix.transpose if axis == 1

        rows, cols = matrix.shape
        target_length = n || rows
        result = Numo::SFloat.zeros(target_length, cols)

        cols.times do |col|
          signal = matrix[true, col].to_a
          transformed = dct_vector(signal, target_length, norm:)
          target_length.times { |idx| result[idx, col] = transformed[idx] }
        end

        axis == 1 ? result.transpose : result
      end

      def dct_vector(signal, n, norm:)
        padded = if signal.length >= n
                   signal[0, n]
                 else
                   signal + Array.new(n - signal.length, 0.0)
                 end

        Array.new(n) do |k|
          sum = 0.0
          n.times do |idx|
            sum += padded[idx] * Math.cos(Math::PI * (idx + 0.5) * k / n)
          end

          normalize_dct(sum, k, n, norm)
        end
      end
      private_class_method :dct_vector

      def normalize_dct(value, index, length, norm)
        return value * 2.0 unless norm == :ortho

        scale = index.zero? ? Math.sqrt(1.0 / length) : Math.sqrt(2.0 / length)
        value * scale
      end
      private_class_method :normalize_dct
    end
  end
end
