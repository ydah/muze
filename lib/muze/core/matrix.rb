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

        _, left_cols = left_matrix.shape
        right_rows, = right_matrix.shape
        raise Muze::ParameterError, "Matrix dimensions do not align" unless left_cols == right_rows

        left_matrix.dot(right_matrix).cast_to(Numo::SFloat)
      end
    end
  end
end
