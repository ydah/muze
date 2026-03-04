# frozen_string_literal: true

module Muze
  module Display
    module_function

    # @param data [Numo::NArray]
    # @param sr [Integer]
    # @param hop_length [Integer]
    # @param x_axis [Symbol]
    # @param y_axis [Symbol]
    # @param output [String, nil]
    # @return [String] SVG content
    def specshow(data, sr: 22_050, hop_length: 512, x_axis: :time, y_axis: :linear, output: nil)
      _ = [sr, hop_length]
      validate_axis!(x_axis:, y_axis:)

      matrix = Numo::SFloat.cast(data)
      matrix = matrix.expand_dims(1) if matrix.ndim == 1
      rows, cols = matrix.shape

      width = 800.0
      height = 400.0
      cell_width = width / [cols, 1].max
      cell_height = height / [rows, 1].max
      min = matrix.min
      max = matrix.max
      range = [max - min, 1.0e-12].max

      rects = []
      rows.times do |row|
        cols.times do |col|
          normalized = (matrix[row, col] - min) / range
          color = heat_color(normalized)
          x = col * cell_width
          y = (rows - row - 1) * cell_height
          rects << "<rect x='#{x.round(3)}' y='#{y.round(3)}' width='#{cell_width.round(3)}' height='#{cell_height.round(3)}' fill='#{color}' />"
        end
      end

      svg = [
        "<svg xmlns='http://www.w3.org/2000/svg' width='#{width.to_i}' height='#{height.to_i}' viewBox='0 0 #{width.to_i} #{height.to_i}'>",
        "<rect width='100%' height='100%' fill='#0b132b' />",
        rects.join,
        "</svg>"
      ].join

      File.write(output, svg) if output
      svg
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param sr [Integer]
    # @param output [String, nil]
    # @return [String] SVG content
    def waveshow(y, sr: 22_050, output: nil)
      _ = sr
      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      width = 800.0
      height = 240.0
      middle = height / 2.0
      step = [signal.length.to_f / width, 1.0].max

      points = []
      x = 0
      while x < width
        sample_index = [((x * step).floor), signal.length - 1].min
        value = signal[sample_index] || 0.0
        y_pos = middle - (value * middle * 0.9)
        points << "#{x.round(2)},#{y_pos.round(2)}"
        x += 1
      end

      svg = [
        "<svg xmlns='http://www.w3.org/2000/svg' width='#{width.to_i}' height='#{height.to_i}' viewBox='0 0 #{width.to_i} #{height.to_i}'>",
        "<rect width='100%' height='100%' fill='#111827' />",
        "<polyline fill='none' stroke='#22d3ee' stroke-width='1.5' points='#{points.join(' ')}' />",
        "</svg>"
      ].join

      File.write(output, svg) if output
      svg
    end

    def validate_axis!(x_axis:, y_axis:)
      raise Muze::ParameterError, "unsupported x_axis" unless %i[time frames].include?(x_axis)
      raise Muze::ParameterError, "unsupported y_axis" unless %i[linear log mel hz].include?(y_axis)
    end
    private_class_method :validate_axis!

    def heat_color(value)
      clamped = [[value, 0.0].max, 1.0].min
      r = (255 * clamped).to_i
      g = (255 * (1.0 - (clamped - 0.5).abs * 2.0)).to_i
      b = (255 * (1.0 - clamped)).to_i
      format("rgb(%<r>d,%<g>d,%<b>d)", r:, g: [g, 0].max, b:)
    end
    private_class_method :heat_color
  end
end
