# frozen_string_literal: true

module Muze
  module Core
    # Short-time Fourier transform and related utilities.
    module STFT
      EPSILON = 1.0e-12
      MAX_N_FFT = 262_144
      FREQUENCY_CACHE = Muze::Core::BoundedCache.new(max_size: 64)
      module_function

      # @param y [Numo::SFloat, Array<Float>] waveform signal
      # @param n_fft [Integer]
      # @param hop_length [Integer]
      # @param win_length [Integer, nil]
      # @param window [Symbol]
      # @param center [Boolean]
      # @param pad_mode [Symbol]
      # @param pad_end [Boolean]
      # @return [Numo::DComplex] shape: [1 + n_fft/2, frames]
      def stft(y, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: true, pad_mode: :reflect, pad_end: false, periodic: false)
        win_length ||= n_fft
        validate_stft_params!(n_fft:, hop_length:, win_length:)
        validate_pad_mode!(pad_mode)

        signal = signal_to_a(y)
        signal = pad_signal(signal, n_fft / 2, pad_mode) if center
        signal = signal.empty? ? [0.0] : signal

        window_values = Muze::Core::Windows.resolve(window, win_length, periodic:).to_a
        window_offset = (n_fft - win_length) / 2
        frame_count = analysis_frame_count(signal.length, n_fft:, hop_length:, pad_end:)

        frequency_bins = (n_fft / 2) + 1
        stft_matrix = Numo::DComplex.zeros(frequency_bins, frame_count)

        frame_count.times do |frame_index|
          frame_start = frame_index * hop_length
          windowed = Array.new(n_fft, 0.0)
          win_length.times do |index|
            frame_index_in_window = index + window_offset
            source_index = frame_start + frame_index_in_window
            sample = source_index < signal.length ? signal[source_index] : 0.0
            windowed[frame_index_in_window] = sample * window_values[index]
          end

          spectrum = fft_real(windowed)
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
      def istft(stft_matrix, hop_length: 512, win_length: nil, window: :hann, center: true, length: nil, dtype: Numo::SFloat, periodic: false)
        stft_matrix = cast_complex_matrix(stft_matrix, "stft_matrix")
        frequency_bins, frame_count = stft_matrix.shape
        n_fft = (frequency_bins - 1) * 2
        win_length ||= n_fft
        validate_stft_params!(n_fft:, hop_length:, win_length:)
        raise Muze::ParameterError, "length must be non-negative" if length && (!length.is_a?(Integer) || length.negative?)

        signal_length = n_fft + (hop_length * [frame_count - 1, 0].max)
        output = Array.new(signal_length, 0.0)
        window_sums = Array.new(signal_length, 0.0)
        window_values = Muze::Core::Windows.resolve(window, win_length, periodic:).to_a
        window_offset = (n_fft - win_length) / 2

        frame_count.times do |frame_index|
          half_spectrum = Array.new(frequency_bins) { |bin| stft_matrix[bin, frame_index] }
          time_domain = ifft_real(half_spectrum).to_a

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
        dtype_class(dtype).cast(output)
      end

      # @param stft_matrix [Numo::DComplex]
      # @param eps [Float]
      # @param dtype [Class, Symbol]
      # @return [Array<Numo::SFloat, Numo::DComplex>]
      def magphase(stft_matrix, eps: EPSILON, dtype: Numo::SFloat)
        unless eps.respond_to?(:positive?) && eps.respond_to?(:finite?) && eps.positive? && eps.finite?
          raise Muze::ParameterError, "eps must be positive"
        end

        stft_matrix = cast_complex_matrix(stft_matrix, "stft_matrix")
        magnitude = stft_matrix.abs.cast_to(dtype_class(dtype))
        phase = stft_matrix / (magnitude + eps)
        [magnitude, phase]
      end

      # @param chunks [Enumerable<Array<Float>, Numo::NArray>]
      # @return [Array<Numo::DComplex>]
      def stft_stream(chunks, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: false, pad_mode: :reflect, periodic: false, flush: true)
        return chunks.map { |chunk| stft(chunk, n_fft:, hop_length:, win_length:, window:, center:, pad_mode:, pad_end: true, periodic:) } if center

        win_length ||= n_fft
        validate_stft_params!(n_fft:, hop_length:, win_length:)
        raise Muze::ParameterError, "flush must be true or false" unless [true, false].include?(flush)

        buffer = []
        results = []
        sentinel = Object.new
        enumerator = chunks.each
        chunk = next_stream_chunk(enumerator, sentinel)

        until chunk.equal?(sentinel)
          following = next_stream_chunk(enumerator, sentinel)
          final = following.equal?(sentinel)
          buffer.concat(signal_to_a(chunk))
          frame_count = stream_frame_count(buffer.length, n_fft:, hop_length:, final: final && flush)
          results << if frame_count.zero?
                       empty_stft_matrix(n_fft)
                     else
                       matrix = stft(buffer, n_fft:, hop_length:, win_length:, window:, center: false, pad_end: final && flush, periodic:)
                       emitted = matrix.shape[1]
                       consumed = final && flush ? buffer.length : emitted * hop_length
                       buffer = buffer[consumed..] || []
                       matrix
                     end
          chunk = following
        end

        results
      end

      # @param s [Numo::NArray]
      # @param ref [Float, Symbol, Proc]
      # @param amin [Float]
      # @param top_db [Float, nil]
      # @param abs [Boolean]
      # @return [Numo::SFloat]
      def amplitude_to_db(s, ref: 1.0, amin: 1.0e-5, top_db: 80.0, abs: false)
        magnitude = if s.is_a?(Numo::DComplex)
                      s.abs.cast_to(Numo::SFloat)
                    else
                      values = Numo::SFloat.cast(s)
                      abs ? values.abs : values
                    end
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
        validate_db_inverse_args!(s_db, ref)
        Numo::SFloat.cast(ref.to_f * Numo::NMath.exp((Numo::SFloat.cast(s_db) / 20.0) * Math.log(10.0)))
      end

      # @param s_db [Numo::NArray]
      # @param ref [Float]
      # @return [Numo::SFloat]
      def db_to_power(s_db, ref: 1.0)
        validate_db_inverse_args!(s_db, ref)
        Numo::SFloat.cast(ref.to_f * Numo::NMath.exp((Numo::SFloat.cast(s_db) / 10.0) * Math.log(10.0)))
      end

      # @param sr [Integer]
      # @param n_fft [Integer]
      # @return [Numo::SFloat]
      def fft_frequencies(sr:, n_fft:)
        raise Muze::ParameterError, "sr must be a positive integer" unless sr.is_a?(Integer) && sr.positive?
        raise Muze::ParameterError, "n_fft must be a positive integer" unless n_fft.is_a?(Integer) && n_fft.positive?

        key = [sr, n_fft]
        FREQUENCY_CACHE.fetch(key) { Numo::SFloat.cast(Array.new((n_fft / 2) + 1) { |index| index * sr.to_f / n_fft }) }.dup
      end

      # @param frames [Integer, Array<Integer>, Numo::NArray]
      # @param sr [Integer]
      # @param hop_length [Integer]
      # @return [Float, Numo::SFloat]
      def frames_to_time(frames, sr:, hop_length:)
        samples_to_time(frames_to_samples(frames, hop_length:), sr:)
      end

      # @param times [Float, Array<Float>, Numo::NArray]
      # @param sr [Integer]
      # @param hop_length [Integer]
      # @return [Integer, Numo::Int64]
      def time_to_frames(times, sr:, hop_length:)
        samples_to_frames(time_to_samples(times, sr:), hop_length:)
      end

      # @param frames [Integer, Array<Integer>, Numo::NArray]
      # @param hop_length [Integer]
      # @return [Integer, Numo::Int64]
      def frames_to_samples(frames, hop_length:)
        raise Muze::ParameterError, "hop_length must be positive" unless hop_length.positive?

        map_scalar_or_array(frames) { |frame| (frame.to_i * hop_length).to_i }
      end

      # @param samples [Integer, Array<Integer>, Numo::NArray]
      # @param hop_length [Integer]
      # @return [Integer, Numo::Int64]
      def samples_to_frames(samples, hop_length:)
        raise Muze::ParameterError, "hop_length must be positive" unless hop_length.positive?

        map_scalar_or_array(samples) { |sample| (sample.to_i / hop_length.to_f).floor }
      end

      def adjust_length(signal, length)
        return signal[0, length] if signal.length >= length

        signal + Array.new(length - signal.length, 0.0)
      end
      private_class_method :adjust_length

      def stream_frame_count(length, n_fft:, hop_length:, final:)
        return final && length.positive? ? 1 : 0 if length <= n_fft
        return (((length - n_fft).to_f / hop_length).ceil + 1) if final

        ((length - n_fft) / hop_length) + 1
      end
      private_class_method :stream_frame_count

      def empty_stft_matrix(n_fft)
        Numo::DComplex.zeros((n_fft / 2) + 1, 0)
      end
      private_class_method :empty_stft_matrix

      def next_stream_chunk(enumerator, sentinel)
        enumerator.next
      rescue StopIteration
        sentinel
      end
      private_class_method :next_stream_chunk

      def analysis_frame_count(length, n_fft:, hop_length:, pad_end:)
        return 1 if length <= n_fft
        return (((length - n_fft).to_f / hop_length).ceil + 1) if pad_end

        ((length - n_fft) / hop_length) + 1
      end
      private_class_method :analysis_frame_count

      def log_scale(values, ref:, amin:, top_db:, multiplier:)
        raise Muze::ParameterError, "amin must be positive" unless amin.positive?
        raise Muze::ParameterError, "top_db must be non-negative" if top_db && top_db.negative?
        validate_finite_values!(values, "input")
        raise Muze::ParameterError, "input values must be non-negative" if contains_negative?(values)

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
                when Numeric then ref.to_f
                else
                  raise Muze::ParameterError, "ref must be numeric, :max, or a Proc"
                end

        raise Muze::ParameterError, "ref must be finite" unless value.finite?

        [value, amin].max
      end
      private_class_method :reference_value

      def validate_stft_params!(n_fft:, hop_length:, win_length:)
        raise Muze::ParameterError, "n_fft must be an integer" unless n_fft.is_a?(Integer)
        raise Muze::ParameterError, "hop_length must be an integer" unless hop_length.is_a?(Integer)
        raise Muze::ParameterError, "win_length must be an integer" unless win_length.is_a?(Integer)
        raise Muze::ParameterError, "n_fft must be positive" if n_fft <= 0
        raise Muze::ParameterError, "n_fft must be <= #{MAX_N_FFT}" if n_fft > MAX_N_FFT
        raise Muze::ParameterError, "n_fft must be even" unless n_fft.even?
        raise Muze::ParameterError, "hop_length must be positive" if hop_length <= 0
        raise Muze::ParameterError, "hop_length must be <= n_fft" if hop_length > n_fft
        raise Muze::ParameterError, "win_length must be between 1 and n_fft" unless win_length.between?(1, n_fft)
      end
      private_class_method :validate_stft_params!

      def validate_pad_mode!(pad_mode)
        return if %i[reflect constant edge].include?(pad_mode)

        raise Muze::ParameterError, "pad_mode must be :reflect, :constant, or :edge"
      end
      private_class_method :validate_pad_mode!

      def signal_to_a(y)
        raise Muze::ParameterError, "y must not be nil" if y.nil?

        signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
        if signal.first.is_a?(Array)
          raise Muze::ParameterError, "stft expects mono audio; process channels separately or downmix first"
        end
        validate_finite_array!(signal, "y")
        signal
      end
      private_class_method :signal_to_a

      def cast_complex_matrix(value, label)
        matrix = Numo::DComplex.cast(value)
        raise Muze::ParameterError, "#{label} must be two-dimensional" unless matrix.ndim == 2
        raise Muze::ParameterError, "#{label} must have at least two frequency bins" if matrix.shape[0] < 2
        validate_finite_array!(matrix.real.to_a.flatten, label)
        validate_finite_array!(matrix.imag.to_a.flatten, label)
        matrix
      rescue NoMethodError, TypeError, ArgumentError => e
        raise Muze::ParameterError, "#{label} must be a complex STFT matrix: #{e.message}"
      end
      private_class_method :cast_complex_matrix

      def validate_db_inverse_args!(values, ref)
        unless ref.respond_to?(:positive?) && ref.respond_to?(:finite?) && ref.positive? && ref.finite?
          raise Muze::ParameterError, "ref must be positive and finite"
        end

        validate_finite_values!(Numo::SFloat.cast(values), "input")
      rescue NoMethodError, TypeError, ArgumentError => e
        raise Muze::ParameterError, "input must contain numeric dB values: #{e.message}"
      end
      private_class_method :validate_db_inverse_args!

      def pad_signal(signal, pad, mode)
        return signal if pad <= 0

        case mode
        when :constant
          Array.new(pad, 0.0) + signal + Array.new(pad, 0.0)
        when :edge
          edge_pad(signal, pad)
        when :reflect
          reflect_pad(signal, pad)
        end
      end
      private_class_method :pad_signal

      def edge_pad(signal, pad)
        return Array.new(pad * 2, 0.0) if signal.empty?

        Array.new(pad, signal.first) + signal + Array.new(pad, signal.last)
      end
      private_class_method :edge_pad

      def reflect_pad(signal, pad)
        return Array.new(pad, 0.0) + signal + Array.new(pad, 0.0) if signal.length <= 1

        front = reflected_values(signal, pad, from_start: true)
        back = reflected_values(signal, pad, from_start: false)
        front + signal + back
      end
      private_class_method :reflect_pad

      def reflected_values(signal, pad, from_start:)
        period = (signal.length - 1) * 2
        Array.new(pad) do |index|
          offset = pad - index
          reflected_index = reflect_index(from_start ? -offset : signal.length - 1 + offset, period)
          signal[reflected_index]
        end
      end
      private_class_method :reflected_values

      def reflect_index(index, period)
        value = index % period
        value = period - value if value >= (period / 2) + 1
        value
      end
      private_class_method :reflect_index

      def fft_real(values)
        Numo::Pocketfft.rfft(Numo::DFloat.cast(values))
      rescue ArgumentError, TypeError => e
        raise Muze::ParameterError, "FFT failed: #{e.message}"
      end
      private_class_method :fft_real

      def ifft_real(values)
        Numo::Pocketfft.irfft(Numo::DComplex.cast(values))
      rescue ArgumentError, TypeError => e
        raise Muze::ParameterError, "inverse FFT failed: #{e.message}"
      end
      private_class_method :ifft_real

      def contains_negative?(values)
        flatten_values(values).any?(&:negative?)
      end
      private_class_method :contains_negative?

      def validate_finite_values!(values, label)
        validate_finite_array!(flatten_values(values), label)
      end
      private_class_method :validate_finite_values!

      def validate_finite_array!(values, label)
        return if values.all? { |value| value.respond_to?(:finite?) && value.finite? }

        raise Muze::ParameterError, "#{label} must contain only finite numeric values"
      end
      private_class_method :validate_finite_array!

      def flatten_values(values)
        values.is_a?(Numo::NArray) ? values.to_a.flatten : Array(values).flatten
      end
      private_class_method :flatten_values

      def time_to_samples(times, sr:)
        raise Muze::ParameterError, "sr must be positive" unless sr.positive?

        map_scalar_or_array(times) { |time| (time.to_f * sr).round }
      end

      def samples_to_time(samples, sr:)
        raise Muze::ParameterError, "sr must be positive" unless sr.positive?

        map_scalar_or_array(samples) { |sample| sample.to_f / sr }
      end

      def map_scalar_or_array(value)
        if value.is_a?(Numo::NArray)
          Numo::SFloat.cast(value.to_a.flatten.map { |item| yield(item) }).reshape(*value.shape)
        elsif value.is_a?(Array)
          Numo::SFloat.cast(value.flatten.map { |item| yield(item) }).reshape(*array_shape(value))
        else
          yield(value)
        end
      end
      private_class_method :map_scalar_or_array

      def array_shape(value)
        return [value.length] unless value.first.is_a?(Array)

        [value.length, value.first.length]
      end
      private_class_method :array_shape

      def dtype_class(dtype)
        case dtype
        when :sfloat, :float32 then Numo::SFloat
        when :dfloat, :float64 then Numo::DFloat
        else
          return Numo::SFloat if dtype == Numo::SFloat
          return Numo::DFloat if dtype == Numo::DFloat

          raise Muze::ParameterError, "dtype must be :sfloat, :float32, :dfloat, :float64, Numo::SFloat, or Numo::DFloat"
        end
      end
      private_class_method :dtype_class
    end
  end
end
