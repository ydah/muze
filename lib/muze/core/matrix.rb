# frozen_string_literal: true

module Muze
  module Core
    # Small dense matrix helpers used by feature extractors.
    module Matrix
      module_function

      def multiply(left, right)
        left_matrix = Numo::SFloat.cast(left)
        right_matrix = Numo::SFloat.cast(right)
        left_matrix = left_matrix.expand_dims(1) if left_matrix.ndim == 1
        right_matrix = right_matrix.expand_dims(1) if right_matrix.ndim == 1

        left_rows, left_cols = left_matrix.shape
        right_rows, right_cols = right_matrix.shape
        raise Muze::ParameterError, "Matrix dimensions do not align" unless left_cols == right_rows

        output = Numo::SFloat.zeros(left_rows, right_cols)

        left_rows.times do |row|
          right_cols.times do |col|
            sum = 0.0
            left_cols.times { |idx| sum += left_matrix[row, idx] * right_matrix[idx, col] }
            output[row, col] = sum
          end
        end

        output
      end
    end
  end
end
