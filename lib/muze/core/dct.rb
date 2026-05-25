# frozen_string_literal: true

module Muze
  module Core
    # DCT utilities.
    module DCT
      BASIS_CACHE = {}
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
        working = adjust_rows(matrix, target_length)
        result = basis_matrix(rows: target_length, cols: target_length, norm:).dot(working).cast_to(Numo::SFloat)

        axis == 1 ? result.transpose : result
      end

      def adjust_rows(matrix, target_length)
        rows, cols = matrix.shape
        return matrix[0...target_length, true] if rows >= target_length

        output = Numo::SFloat.zeros(target_length, cols)
        output[0...rows, true] = matrix
        output
      end
      private_class_method :adjust_rows

      def basis_matrix(rows:, cols:, norm:)
        key = [rows, cols, norm]
        (BASIS_CACHE[key] ||= begin
          matrix = Numo::SFloat.zeros(rows, cols)
          rows.times do |row|
            cols.times do |col|
              value = Math.cos(Math::PI * (col + 0.5) * row / cols)
              matrix[row, col] = normalize_dct(value, row, cols, norm)
            end
          end
          matrix
        end)
      end
      private_class_method :basis_matrix

      def normalize_dct(value, index, length, norm)
        return value * 2.0 unless norm == :ortho

        scale = index.zero? ? Math.sqrt(1.0 / length) : Math.sqrt(2.0 / length)
        value * scale
      end
      private_class_method :normalize_dct
    end
  end
end
