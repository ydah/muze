# frozen_string_literal: true

module Muze
  module Core
    # Shared fixed-size frame slicing for analysis and effects code.
    module Frames
      module_function

      def slice(signal, frame_length:, hop_length:, pad_end: false)
        raise Muze::ParameterError, "frame_length and hop_length must be positive" unless frame_length.positive? && hop_length.positive?

        values = signal.is_a?(Numo::NArray) ? signal.to_a : Array(signal)
        return [pad_frame(values, frame_length)] if values.length <= frame_length
        return Muze::Native.frame_slices(values, frame_length, hop_length) unless pad_end

        frame_count = ((values.length - frame_length).to_f / hop_length).ceil + 1
        Array.new(frame_count) do |index|
          start = index * hop_length
          pad_frame(values[start, frame_length] || [], frame_length)
        end
      end

      def pad_frame(frame, frame_length)
        return frame if frame.length >= frame_length

        frame + Array.new(frame_length - frame.length, 0.0)
      end
      private_class_method :pad_frame
    end
  end
end
