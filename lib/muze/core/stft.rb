# frozen_string_literal: true

module Muze
  module Core
    # Short-time Fourier transform and related utilities.
    module STFT
      EPSILON = 1.0e-12
      module_function

      # @param y [Numo::SFloat, Array<Float>] waveform signal
      # @param n_fft [Integer]
      # @param hop_length [Integer]
      # @param win_length [Integer, nil]
      # @param window [Symbol]
      # @param center [Boolean]
      # @param pad_mode [Symbol]
      # @return [Numo::DComplex] shape: [1 + n_fft/2, frames]
      def stft(y, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: true, pad_mode: :reflect)
        win_length ||= n_fft
        validate_stft_params!(n_fft:, hop_length:, win_length:)

        signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
        signal = reflect_pad(signal, n_fft / 2) if center
        signal = signal.empty? ? [0.0] : signal

        frames = frame_signal(signal, n_fft, hop_length)
        window_values = Muze::Core::Windows.resolve(window, win_length).to_a
        window_offset = (n_fft - win_length) / 2

        frequency_bins = (n_fft / 2) + 1
        stft_matrix = Numo::DComplex.zeros(frequency_bins, frames.length)

        frames.each_with_index do |frame, frame_index|
          windowed = Array.new(n_fft, 0.0)
          win_length.times do |index|
            frame_index_in_window = index + window_offset
            windowed[frame_index_in_window] = frame[frame_index_in_window] * window_values[index]
          end

          spectrum = fft_complex(windowed.map { |value| Complex(value, 0.0) })
          frequency_bins.times { |bin| stft_matrix[bin, frame_index] = spectrum[bin] }
        end

        stft_matrix
      end

      # @param stft_matrix [Numo::DComplex]
      # @param hop_length [Integer]
      # @param win_length [Integer, nil]
      # @param window [Symbol]
      # @param center [Boolean]
      # @param length [Integer, nil]
      # @return [Numo::SFloat]
      def istft(stft_matrix, hop_length: 512, win_length: nil, window: :hann, center: true, length: nil)
        frequency_bins, frame_count = stft_matrix.shape
        n_fft = (frequency_bins - 1) * 2
        win_length ||= n_fft
        validate_stft_params!(n_fft:, hop_length:, win_length:)

        signal_length = n_fft + (hop_length * [frame_count - 1, 0].max)
        output = Array.new(signal_length, 0.0)
        window_sums = Array.new(signal_length, 0.0)
        window_values = Muze::Core::Windows.resolve(window, win_length).to_a
        window_offset = (n_fft - win_length) / 2

        frame_count.times do |frame_index|
          half_spectrum = Array.new(frequency_bins) { |bin| stft_matrix[bin, frame_index] }
          mirrored = half_spectrum[1...-1].reverse.map(&:conj)
          full_spectrum = half_spectrum + mirrored
          time_domain = ifft_complex(full_spectrum).map(&:real)

          win_length.times do |index|
            output_index = (frame_index * hop_length) + index + window_offset
            break if output_index >= signal_length

            window_value = window_values[index]
            frame_value = time_domain[index + window_offset]
            output[output_index] += frame_value * window_value
            window_sums[output_index] += window_value * window_value
          end
        end

        output.map!.with_index do |value, index|
          denominator = window_sums[index]
          denominator > EPSILON ? (value / denominator) : value
        end

        if center
          pad = n_fft / 2
          output = output[pad...(output.length - pad)] || []
        end

        output = adjust_length(output, length) if length
        Numo::SFloat.cast(output)
      end

      # @param stft_matrix [Numo::DComplex]
      # @return [Array<Numo::SFloat, Numo::DComplex>]
      def magphase(stft_matrix)
        magnitude = stft_matrix.abs.cast_to(Numo::SFloat)
        phase = stft_matrix / (magnitude + EPSILON)
        [magnitude, phase]
      end

      # @param s [Numo::NArray]
      # @param ref [Float, Symbol, Proc]
      # @param amin [Float]
      # @param top_db [Float, nil]
      # @return [Numo::SFloat]
      def amplitude_to_db(s, ref: 1.0, amin: 1.0e-5, top_db: 80.0)
        magnitude = s.is_a?(Numo::DComplex) ? s.abs.cast_to(Numo::SFloat) : Numo::SFloat.cast(s)
        log_scale(magnitude, ref:, amin:, top_db:, multiplier: 20.0)
      end

      # @param s [Numo::NArray]
      # @param ref [Float, Symbol, Proc]
      # @param amin [Float]
      # @param top_db [Float, nil]
      # @return [Numo::SFloat]
      def power_to_db(s, ref: 1.0, amin: 1.0e-10, top_db: 80.0)
        power = Numo::SFloat.cast(s)
        log_scale(power, ref:, amin:, top_db:, multiplier: 10.0)
      end

      # @param s_db [Numo::NArray]
      # @param ref [Float]
      # @return [Numo::SFloat]
      def db_to_amplitude(s_db, ref: 1.0)
        Numo::SFloat.cast(ref.to_f * Numo::NMath.exp((Numo::SFloat.cast(s_db) / 20.0) * Math.log(10.0)))
      end

      # @param s_db [Numo::NArray]
      # @param ref [Float]
      # @return [Numo::SFloat]
      def db_to_power(s_db, ref: 1.0)
        Numo::SFloat.cast(ref.to_f * Numo::NMath.exp((Numo::SFloat.cast(s_db) / 10.0) * Math.log(10.0)))
      end

      def adjust_length(signal, length)
        return signal[0, length] if signal.length >= length

        signal + Array.new(length - signal.length, 0.0)
      end
      private_class_method :adjust_length

      def log_scale(values, ref:, amin:, top_db:, multiplier:)
        clipped = values.clip(amin, Float::INFINITY)
        reference = reference_value(ref, clipped, amin)
        base = multiplier * Math.log10(reference)
        db = (multiplier * Numo::NMath.log10(clipped)) - base

        return db.cast_to(Numo::SFloat) if top_db.nil?

        floor = db.max - top_db
        db.clip(floor, Float::INFINITY).cast_to(Numo::SFloat)
      end
      private_class_method :log_scale

      def reference_value(ref, values, amin)
        value = case ref
                when :max then values.max
                when Proc then ref.call(values)
                else
                  ref.to_f
                end

        [value, amin].max
      end
      private_class_method :reference_value

      def validate_stft_params!(n_fft:, hop_length:, win_length:)
        raise Muze::ParameterError, "n_fft must be positive" if n_fft <= 0
        raise Muze::ParameterError, "n_fft must be a power of two" unless power_of_two?(n_fft)
        raise Muze::ParameterError, "hop_length must be positive" if hop_length <= 0
        raise Muze::ParameterError, "hop_length must be <= n_fft" if hop_length > n_fft
        raise Muze::ParameterError, "win_length must be between 1 and n_fft" unless win_length.between?(1, n_fft)
      end
      private_class_method :validate_stft_params!

      def power_of_two?(value)
        (value & (value - 1)).zero?
      end
      private_class_method :power_of_two?

      def frame_signal(signal, n_fft, hop_length)
        return [signal + Array.new(n_fft - signal.length, 0.0)] if signal.length <= n_fft

        frame_count = ((signal.length - n_fft) / hop_length) + 1
        Array.new(frame_count) do |index|
          start = index * hop_length
          signal[start, n_fft]
        end
      end
      private_class_method :frame_signal

      def reflect_pad(signal, pad)
        return signal if pad <= 0 || signal.length <= 1

        front = signal[1, pad].to_a.reverse
        back = signal[-(pad + 1), pad].to_a.reverse
        front + signal + back
      end
      private_class_method :reflect_pad

      def fft_complex(values)
        length = values.length
        return values if length <= 1

        raise Muze::ParameterError, "FFT length must be a power of two" unless power_of_two?(length)

        even = fft_complex(values.values_at(*0.step(length - 1, 2)))
        odd = fft_complex(values.values_at(*1.step(length - 1, 2)))

        output = Array.new(length)
        half = length / 2

        half.times do |k|
          twiddle = Complex.polar(1.0, -2.0 * Math::PI * k / length) * odd[k]
          output[k] = even[k] + twiddle
          output[k + half] = even[k] - twiddle
        end

        output
      end
      private_class_method :fft_complex

      def ifft_complex(values)
        conjugated = values.map(&:conj)
        transformed = fft_complex(conjugated)
        scale = values.length.to_f
        transformed.map { |value| value.conj / scale }
      end
      private_class_method :ifft_complex
    end
  end
end
