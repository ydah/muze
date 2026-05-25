# frozen_string_literal: true

module Muze
  module Feature
    module_function

    # Beat-synchronous aggregation over the frame axis.
    def beat_sync(data, beats:, aggregate: :mean)
      raise Muze::ParameterError, "aggregate must be :mean, :median, or :max" unless %i[mean median max].include?(aggregate)

      matrix = Numo::SFloat.cast(data)
      matrix = matrix.expand_dims(0) if matrix.ndim == 1
      raise Muze::ParameterError, "data must be one- or two-dimensional" unless [1, 2].include?(matrix.ndim)

      rows, frames = matrix.shape
      boundaries = beat_boundaries(beats, frames)
      output = Numo::SFloat.zeros(rows, boundaries.length - 1)

      boundaries.each_cons(2).with_index do |(left, right), segment_index|
        rows.times do |row|
          values = matrix[row, left...right].to_a
          output[row, segment_index] = aggregate_values(values, aggregate:)
        end
      end

      output
    end

    def beat_boundaries(beats, frames)
      points = Array(beats).map(&:to_i).select { |beat| beat.between?(0, frames) }
      ([0] + points + [frames]).uniq.sort
    end
    private_class_method :beat_boundaries

    def aggregate_values(values, aggregate:)
      return 0.0 if values.empty?

      case aggregate
      when :mean
        values.sum(0.0) / values.length
      when :median
        Muze::Native.median1d(values)
      when :max
        values.max
      end
    end
    private_class_method :aggregate_values
  end
end
