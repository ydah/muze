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
    def specshow(data, sr: 22_050, hop_length: 512, x_axis: :time, y_axis: :linear, output: nil, width: 800, height: 400, cmap: :heat, vmin: nil, vmax: nil)
      validate_axis!(x_axis:, y_axis:)
      raise Muze::ParameterError, "width and height must be positive" unless width.positive? && height.positive?

      matrix = Numo::SFloat.cast(data)
      matrix = matrix.expand_dims(1) if matrix.ndim == 1
      matrix = downsample_matrix(matrix, max_cells: 12_000)
      rows, cols = matrix.shape

      width = width.to_f
      height = height.to_f
      cell_width = width / [cols, 1].max
      min = vmin || matrix.min
      max = vmax || matrix.max
      range = [max - min, 1.0e-12].max

      rects = []
      rows.times do |row|
        y_top = y_position(row + 1, rows, height, y_axis:, sr:)
        y_bottom = y_position(row, rows, height, y_axis:, sr:)
        cell_height = [y_bottom - y_top, 0.1].max
        cols.times do |col|
          normalized = (matrix[row, col] - min) / range
          color = color_for(normalized, cmap:)
          x = x_position(col, cols, width, hop_length:, sr:, x_axis:)
          next_x = x_position(col + 1, cols, width, hop_length:, sr:, x_axis:)
          rect_width = [next_x - x, 0.1].max
          y = y_top
          rects << "<rect x='#{x.round(3)}' y='#{y.round(3)}' width='#{rect_width.round(3)}' height='#{cell_height.round(3)}' fill='#{color}' />"
        end
      end

      svg = [
        "<svg xmlns='http://www.w3.org/2000/svg' width='#{width.to_i}' height='#{height.to_i}' viewBox='0 0 #{width.to_i} #{height.to_i}'>",
        "<rect width='100%' height='100%' fill='#0b132b' />",
        "<g data-x-axis='#{x_axis}' data-y-axis='#{y_axis}' data-sr='#{sr}' data-hop-length='#{hop_length}'>",
        rects.join,
        "</g>",
        "</svg>"
      ].join

      write_output(output, svg) if output
      svg
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param sr [Integer]
    # @param output [String, nil]
    # @return [String] SVG content
    def waveshow(y, sr: 22_050, output: nil, width: 800, height: 240, normalize: true, channels: :overlay)
      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      raise Muze::ParameterError, "channels must be :overlay or :split" unless %i[overlay split].include?(channels)

      channel_data = signal.first.is_a?(Array) ? transpose_channels(signal) : [signal]
      channel_data = channel_data.map { |channel| normalize ? normalize_wave(channel) : channel }
      width = width.to_f
      height = height.to_f
      middle = height / 2.0
      paths = channel_data.each_with_index.map do |channel, index|
        top, lane_height = channel_lane(index, channel_data.length, height, channels:)
        envelope_path(channel, width:, top:, height: lane_height)
      end

      svg = [
        "<svg xmlns='http://www.w3.org/2000/svg' width='#{width.to_i}' height='#{height.to_i}' viewBox='0 0 #{width.to_i} #{height.to_i}'>",
        "<rect width='100%' height='100%' fill='#111827' />",
        "<g data-sr='#{sr}' data-channels='#{channels}' transform='translate(0 #{middle * 0.0})'>",
        paths.join,
        "</g>",
        "</svg>"
      ].join

      write_output(output, svg) if output
      svg
    end

    def validate_axis!(x_axis:, y_axis:)
      raise Muze::ParameterError, "unsupported x_axis" unless %i[time frames].include?(x_axis)
      raise Muze::ParameterError, "unsupported y_axis" unless %i[linear log mel hz].include?(y_axis)
    end
    private_class_method :validate_axis!

    def color_for(value, cmap:)
      case cmap
      when :heat then heat_color(value)
      when :gray, :grey then gray_color(value)
      when :magma then magma_color(value)
      else
        raise Muze::ParameterError, "unsupported cmap"
      end
    end
    private_class_method :color_for

    def heat_color(value)
      clamped = [[value, 0.0].max, 1.0].min
      r = (255 * clamped).to_i
      g = (255 * (1.0 - (clamped - 0.5).abs * 2.0)).to_i
      b = (255 * (1.0 - clamped)).to_i
      format("rgb(%<r>d,%<g>d,%<b>d)", r:, g: [g, 0].max, b:)
    end
    private_class_method :heat_color

    def gray_color(value)
      level = (255 * [[value, 0.0].max, 1.0].min).to_i
      format("rgb(%<v>d,%<v>d,%<v>d)", v: level)
    end
    private_class_method :gray_color

    def magma_color(value)
      clamped = [[value, 0.0].max, 1.0].min
      r = (252 * clamped).to_i
      g = (80 * (clamped**1.5)).to_i
      b = (120 * (1.0 - clamped) + 40).to_i
      format("rgb(%<r>d,%<g>d,%<b>d)", r:, g:, b:)
    end
    private_class_method :magma_color

    def x_position(col, cols, width, hop_length:, sr:, x_axis:)
      return col * width / [cols, 1].max if x_axis == :frames

      total_time = [cols * hop_length.to_f / sr, 1.0e-12].max
      (col * hop_length.to_f / sr) * width / total_time
    end
    private_class_method :x_position

    def y_position(row, rows, height, y_axis:, sr:)
      normalized = case y_axis
                   when :linear, :hz
                     row.to_f / [rows, 1].max
                   when :mel
                     hz = row * (sr / 2.0) / [rows, 1].max
                     Muze::Filters.hz_to_mel(hz) / Muze::Filters.hz_to_mel(sr / 2.0)
                   when :log
                     Math.log10(1.0 + (9.0 * row / [rows, 1].max.to_f))
                   end
      height - (normalized * height)
    end
    private_class_method :y_position

    def downsample_matrix(matrix, max_cells:)
      rows, cols = matrix.shape
      return matrix if rows * cols <= max_cells

      col_step = [(rows * cols / max_cells.to_f).ceil, 1].max
      selected_cols = (0...cols).step(col_step).to_a
      output = Numo::SFloat.zeros(rows, selected_cols.length)
      selected_cols.each_with_index { |col, index| output[true, index] = matrix[true, col] }
      output
    end
    private_class_method :downsample_matrix

    def transpose_channels(samples)
      channel_count = samples.first.length
      Array.new(channel_count) { |channel| samples.map { |frame| frame[channel] } }
    end
    private_class_method :transpose_channels

    def normalize_wave(channel)
      peak = channel.map(&:abs).max || 0.0
      return channel if peak <= 0.0

      channel.map { |value| value / peak }
    end
    private_class_method :normalize_wave

    def channel_lane(index, count, height, channels:)
      return [0.0, height] if channels == :overlay

      lane_height = height / count
      [index * lane_height, lane_height]
    end
    private_class_method :channel_lane

    def envelope_path(channel, width:, top:, height:)
      middle = top + (height / 2.0)
      step = [channel.length.to_f / width, 1.0].max
      segments = []

      x = 0
      while x < width
        start_index = (x * step).floor
        end_index = [((x + 1) * step).ceil, channel.length].min
        window = channel[start_index...end_index] || [0.0]
        min = window.min || 0.0
        max = window.max || 0.0
        y_min = middle - (min * height * 0.45)
        y_max = middle - (max * height * 0.45)
        segments << "M #{x.round(2)} #{y_min.round(2)} L #{x.round(2)} #{y_max.round(2)}"
        x += 1
      end

      "<path d='#{segments.join(' ')}' fill='none' stroke='#22d3ee' stroke-width='1.2' />"
    end
    private_class_method :envelope_path

    def write_output(output, svg)
      path = output.respond_to?(:to_path) ? output.to_path : output
      File.write(path, svg)
    rescue SystemCallError => e
      raise Muze::Error, "Failed to write SVG output #{path}: #{e.message}"
    end
    private_class_method :write_output
  end
end
