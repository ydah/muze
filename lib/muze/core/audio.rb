# frozen_string_literal: true

module Muze
  module Core
    # Small audio-array helpers shared by public convenience APIs.
    module Audio
      module_function

      def validate_audio!(y, allow_empty: false)
        raise Muze::ParameterError, "audio must not be nil" if y.nil?

        signal = Numo::SFloat.cast(y)
        raise Muze::ParameterError, "audio must be one- or two-dimensional" unless [1, 2].include?(signal.ndim)
        raise Muze::ParameterError, "audio must not be empty" if !allow_empty && signal.empty?
        raise Muze::ParameterError, "audio must contain only finite numeric values" unless finite_values?(signal)
        raise Muze::ParameterError, "audio channel count must be positive" if signal.ndim == 2 && signal.shape[1].zero?

        signal
      rescue NoMethodError, TypeError, ArgumentError => e
        raise Muze::ParameterError, "audio must be Array<Float> or Numo::NArray: #{e.message}"
      end

      def valid_audio?(y, allow_empty: false)
        validate_audio!(y, allow_empty:)
        true
      rescue Muze::ParameterError
        false
      end

      def normalize(y, peak: 1.0, axis: nil)
        raise Muze::ParameterError, "peak must be positive" unless peak.respond_to?(:positive?) && peak.positive?
        raise Muze::ParameterError, "axis must be nil or :channels" unless axis.nil? || axis == :channels

        signal = validate_audio!(y, allow_empty: true)
        return signal if signal.empty?

        return normalize_channels(signal, peak:) if axis == :channels && signal.ndim == 2

        current_peak = signal.abs.max.to_f
        return signal if current_peak <= 0.0

        (signal * (peak.to_f / current_peak)).cast_to(Numo::SFloat)
      end

      def remix(y, intervals, units: :samples, sr: nil, hop_length: 512)
        signal = validate_audio!(y, allow_empty: true)
        raw_intervals = intervals.respond_to?(:to_a) ? intervals.to_a : Array(intervals)
        raw_intervals = [raw_intervals] if raw_intervals.length == 2 && !raw_intervals.first.respond_to?(:to_a)

        sample_ranges = raw_intervals.map do |interval|
          raise Muze::ParameterError, "intervals must contain [start, end] pairs" unless interval.respond_to?(:to_a) && interval.to_a.length == 2

          start_sample = convert_position(interval.to_a[0], units:, sr:, hop_length:)
          end_sample = convert_position(interval.to_a[1], units:, sr:, hop_length:)
          raise Muze::ParameterError, "interval end must be >= start" if end_sample < start_sample

          [start_sample, end_sample]
        end

        chunks = sample_ranges.map { |start_sample, end_sample| slice_samples(signal, start_sample, end_sample) }
        concatenate_chunks(chunks, channel_count: signal.ndim == 2 ? signal.shape[1] : nil)
      end

      def finite_values?(signal)
        signal.to_a.flatten.all? { |value| value.respond_to?(:finite?) && value.finite? }
      end
      private_class_method :finite_values?

      def normalize_channels(signal, peak:)
        frames, channels = signal.shape
        output = Numo::SFloat.zeros(frames, channels)
        channels.times do |channel|
          values = signal[true, channel]
          current_peak = values.abs.max.to_f
          output[true, channel] = current_peak <= 0.0 ? values : values * (peak.to_f / current_peak)
        end
        output
      end
      private_class_method :normalize_channels

      def convert_position(position, units:, sr:, hop_length:)
        case units
        when :samples
          position.to_i
        when :frames
          raise Muze::ParameterError, "hop_length must be positive" unless hop_length.positive?

          (position.to_i * hop_length).to_i
        when :time
          raise Muze::ParameterError, "sr must be positive for time units" unless sr&.positive?

          (position.to_f * sr).round
        else
          raise Muze::ParameterError, "units must be :samples, :frames, or :time"
        end
      end
      private_class_method :convert_position

      def slice_samples(signal, start_sample, end_sample)
        start_index = [[start_sample, 0].max, signal.shape[0]].min
        end_index = [[end_sample, 0].max, signal.shape[0]].min
        return signal.ndim == 2 ? Numo::SFloat.zeros(0, signal.shape[1]) : Numo::SFloat[] if end_index <= start_index

        signal.ndim == 2 ? signal[start_index...end_index, true] : signal[start_index...end_index]
      end
      private_class_method :slice_samples

      def concatenate_chunks(chunks, channel_count:)
        return channel_count ? Numo::SFloat.zeros(0, channel_count) : Numo::SFloat[] if chunks.empty?

        total = chunks.sum { |chunk| channel_count ? chunk.shape[0] : chunk.size }
        if channel_count
          output = Numo::SFloat.zeros(total, channel_count)
          offset = 0
          chunks.each do |chunk|
            next if chunk.shape[0].zero?

            output[offset...(offset + chunk.shape[0]), true] = chunk
            offset += chunk.shape[0]
          end
          return output
        end

        Numo::SFloat.cast(chunks.flat_map(&:to_a))
      end
      private_class_method :concatenate_chunks
    end
  end
end
