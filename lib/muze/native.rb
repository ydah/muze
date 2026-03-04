# frozen_string_literal: true

module Muze
  # Optional native extension wrapper.
  module Native
    module_function

    begin
      require "muze/muze_ext"
      EXTENSION_LOADED = true
    rescue LoadError
      EXTENSION_LOADED = false
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
        sorted = values.sort
        sorted[sorted.length / 2] || 0.0
      end
    end
  end
end
