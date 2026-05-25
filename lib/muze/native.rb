# frozen_string_literal: true

module Muze
  # Optional native extension wrapper.
  module Native
    module_function

    EXTENSION_LOADED = if ENV.fetch("MUZE_DISABLE_NATIVE", "0") == "1"
                         false
                       else
                         begin
                           require "muze/muze_ext"
                           true
                         rescue LoadError
                           false
                         end
                       end

    # @return [Boolean]
    def extension_loaded?
      EXTENSION_LOADED
    end

    unless EXTENSION_LOADED
      # @param signal [Array<Float>]
      # @param frame_length [Integer]
      # @param hop_length [Integer]
      # @return [Array<Array<Float>>]
      def frame_slices(signal, frame_length, hop_length)
        raise Muze::ParameterError, "signal must be an Array" unless signal.is_a?(Array)
        unless frame_length.is_a?(Integer) && hop_length.is_a?(Integer) && frame_length.positive? && hop_length.positive?
          raise Muze::ParameterError, "frame_length and hop_length must be positive"
        end

        if signal.length <= frame_length
          return [signal + Array.new(frame_length - signal.length, 0.0)]
        end

        frame_count = ((signal.length - frame_length) / hop_length) + 1
        Array.new(frame_count) do |index|
          start = index * hop_length
          signal[start, frame_length]
        end
      end

      # @param values [Array<Float>]
      # @return [Float]
      def median1d(values)
        raise Muze::ParameterError, "values must be an Array" unless values.is_a?(Array)
        return 0.0 if values.empty?

        copy = values.map(&:to_f)
        quickselect!(copy, copy.length / 2)
      end

      # @param values [Array<Float>]
      # @param half [Integer]
      # @return [Array<Float>]
      def median_filter1d(values, half)
        raise Muze::ParameterError, "values must be an Array" unless values.is_a?(Array)
        raise Muze::ParameterError, "half must be non-negative" unless half.is_a?(Integer) && half >= 0
        return [] if values.empty?

        window = []
        output = Array.new(values.length, 0.0)
        values.length.times do |index|
          remove_sorted_value(window, values[index - half - 1]) if index > half
          entering = index + half
          insert_sorted_value(window, values[entering]) if entering < values.length
          output[index] = window[window.length / 2].to_f
        end

        output
      end

      def quickselect!(values, target)
        left = 0
        right = values.length - 1

        loop do
          return values[left] if left == right

          pivot_index = partition!(values, left, right, (left + right) / 2)
          if target == pivot_index
            return values[target]
          elsif target < pivot_index
            right = pivot_index - 1
          else
            left = pivot_index + 1
          end
        end
      end
      private_class_method :quickselect!

      def partition!(values, left, right, pivot_index)
        pivot = values[pivot_index]
        values[pivot_index], values[right] = values[right], values[pivot_index]
        store_index = left

        (left...right).each do |index|
          next unless values[index] < pivot

          values[store_index], values[index] = values[index], values[store_index]
          store_index += 1
        end

        values[right], values[store_index] = values[store_index], values[right]
        store_index
      end
      private_class_method :partition!

      def insert_sorted_value(sorted, value)
        index = sorted.bsearch_index { |item| item > value } || sorted.length
        sorted.insert(index, value)
      end
      private_class_method :insert_sorted_value

      def remove_sorted_value(sorted, value)
        index = sorted.bsearch_index { |item| item >= value }
        return unless index

        index += 1 while index < sorted.length && sorted[index] != value
        sorted.delete_at(index) if index < sorted.length
      end
      private_class_method :remove_sorted_value
    end
  end
end
