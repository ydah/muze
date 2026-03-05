# frozen_string_literal: true

module Muze
  module Effects
    module_function

    # Keep fast path for short clips where phase vocoder overhead dominates.
    MIN_PHASE_VOCODER_SAMPLES = 32_768

    # @param y [Numo::SFloat, Array<Float>]
    # @param rate [Float]
    # @return [Numo::SFloat]
    def time_stretch(y, rate: 1.0)
      raise Muze::ParameterError, "rate must be positive" unless rate.positive?

      signal = y.is_a?(Numo::NArray) ? Numo::SFloat.cast(y) : Numo::SFloat.cast(Array(y))
      return signal if signal.empty? || rate == 1.0
      return linear_time_stretch(signal.to_a, rate) if signal.size < MIN_PHASE_VOCODER_SAMPLES

      n_fft = phase_vocoder_fft_size(signal.size)
      hop_length = [n_fft / 4, 1].max

      stft_matrix = Muze::Core::STFT.stft(signal, n_fft:, hop_length:, center: true)
      stretched_stft = phase_vocoder(stft_matrix, rate:, hop_length:, n_fft:)
      target_length = [(signal.size / rate).round, 1].max

      Muze::Core::STFT.istft(stretched_stft, hop_length:, center: true, length: target_length)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param sr [Integer]
    # @param n_steps [Float]
    # @return [Numo::SFloat]
    def pitch_shift(y, sr: 22_050, n_steps: 0)
      _ = sr
      signal = y.is_a?(Numo::NArray) ? y : Numo::SFloat.cast(y)
      return signal if n_steps.zero?

      rate = 2.0**(-n_steps.to_f / 12.0)
      stretched = time_stretch(signal, rate:)
      preferred_res_type = signal.size >= MIN_PHASE_VOCODER_SAMPLES ? :sinc : :linear
      restored = resample_for_pitch_shift(stretched, target_size: signal.size, preferred_res_type:)
      Numo::SFloat.cast(restored[0...signal.size])
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param top_db [Float]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Array(Numo::SFloat, Array<Integer>)] trimmed signal and [start, end]
    def trim(y, top_db: 60, frame_length: 2048, hop_length: 512)
      _ = [frame_length, hop_length]
      signal = y.is_a?(Numo::NArray) ? y : Numo::SFloat.cast(y)
      abs_signal = signal.abs
      threshold = [abs_signal.max, 1.0e-12].max * (10.0**(-top_db / 20.0))
      indices = abs_signal.to_a.each_index.select { |index| abs_signal[index] >= threshold }
      return [Numo::SFloat[], [0, 0]] if indices.empty?

      start_sample = indices.first
      end_sample = indices.last + 1
      [signal[start_sample...end_sample], [start_sample, end_sample]]
    end

    # @param signal_length [Integer]
    # @return [Integer]
    def phase_vocoder_fft_size(signal_length)
      max_fft = [signal_length, 2048].min
      fft_size = 1
      fft_size *= 2 while (fft_size * 2) <= max_fft
      [fft_size, 32].max
    end
    private_class_method :phase_vocoder_fft_size

    # @param stft_matrix [Numo::DComplex]
    # @param rate [Float]
    # @param hop_length [Integer]
    # @param n_fft [Integer]
    # @return [Numo::DComplex]
    def phase_vocoder(stft_matrix, rate:, hop_length:, n_fft:)
      frequency_bins, frame_count = stft_matrix.shape
      return stft_matrix if frame_count <= 1

      time_steps = []
      position = 0.0
      max_frame = frame_count - 1
      while position <= max_frame
        time_steps << position
        position += rate
      end

      stretched = Numo::DComplex.zeros(frequency_bins, time_steps.length)
      phase_advance = Array.new(frequency_bins) { |bin| (2.0 * Math::PI * hop_length * bin) / n_fft }
      phase_accumulator = Array.new(frequency_bins) { |bin| phase_of(stft_matrix[bin, 0]) }

      time_steps.each_with_index do |step, output_index|
        if output_index.zero?
          frequency_bins.times { |bin| stretched[bin, output_index] = stft_matrix[bin, 0] }
          next
        end

        frame_index = step.floor
        next_frame_index = [frame_index + 1, frame_count - 1].min
        alpha = step - frame_index

        frequency_bins.times do |bin|
          current = stft_matrix[bin, frame_index]
          following = stft_matrix[bin, next_frame_index]
          magnitude = ((1.0 - alpha) * current.abs) + (alpha * following.abs)

          phase_delta = phase_of(following) - phase_of(current) - phase_advance[bin]
          phase_delta = wrap_phase(phase_delta)
          phase_accumulator[bin] += phase_advance[bin] + phase_delta

          stretched[bin, output_index] = Complex.polar(magnitude, phase_accumulator[bin])
        end
      end

      stretched
    end
    private_class_method :phase_vocoder

    # @param complex_number [Complex]
    # @return [Float]
    def phase_of(complex_number)
      Math.atan2(complex_number.imag, complex_number.real)
    end
    private_class_method :phase_of

    # @param phase [Float]
    # @return [Float]
    def wrap_phase(phase)
      ((phase + Math::PI) % (2.0 * Math::PI)) - Math::PI
    end
    private_class_method :wrap_phase

    # @param signal [Array<Float>]
    # @param rate [Float]
    # @return [Numo::SFloat]
    def linear_time_stretch(signal, rate)
      target_length = [(signal.length / rate).round, 1].max
      stretched = Array.new(target_length, 0.0)

      target_length.times do |index|
        source_position = index * rate
        left = source_position.floor
        right = [left + 1, signal.length - 1].min
        alpha = source_position - left
        stretched[index] = ((1.0 - alpha) * signal[left]) + (alpha * signal[right])
      end

      Numo::SFloat.cast(stretched)
    end
    private_class_method :linear_time_stretch

    # Prefer sinc-quality resampling, then fall back to linear on failure.
    # @param stretched [Numo::SFloat]
    # @param target_size [Integer]
    # @param preferred_res_type [Symbol]
    # @return [Numo::SFloat]
    def resample_for_pitch_shift(stretched, target_size:, preferred_res_type:)
      if preferred_res_type == :sinc
        return Muze::Core::Resample.resample(stretched, orig_sr: stretched.size, target_sr: target_size, res_type: :sinc)
      end

      Muze::Core::Resample.resample(stretched, orig_sr: stretched.size, target_sr: target_size, res_type: :linear)
    rescue Muze::Error, StandardError
      Muze::Core::Resample.resample(stretched, orig_sr: stretched.size, target_sr: target_size, res_type: :linear)
    end
    private_class_method :resample_for_pitch_shift
  end
end
