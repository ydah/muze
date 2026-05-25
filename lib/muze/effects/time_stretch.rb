# frozen_string_literal: true

module Muze
  module Effects
    module_function

    # Keep fast path for short clips where phase vocoder overhead dominates.
    MIN_PHASE_VOCODER_SAMPLES = 32_768
    MIN_TIME_STRETCH_RATE = 1.0 / 32.0
    MAX_TIME_STRETCH_RATE = 32.0

    # @param y [Numo::SFloat, Array<Float>]
    # @param rate [Float]
    # @return [Numo::SFloat]
    def time_stretch(y, rate: 1.0, n_fft: nil, hop_length: nil, method: :phase_vocoder, phase_lock: false, force_phase_vocoder: false)
      validate_positive_number!(rate, "rate")
      unless rate.between?(MIN_TIME_STRETCH_RATE, MAX_TIME_STRETCH_RATE)
        raise Muze::ParameterError, "rate must be between #{MIN_TIME_STRETCH_RATE} and #{MAX_TIME_STRETCH_RATE}"
      end
      validate_optional_positive_integer!(n_fft, "n_fft")
      validate_optional_positive_integer!(hop_length, "hop_length")
      raise Muze::ParameterError, "method must be :phase_vocoder, :ola, :wsola, or :linear" unless %i[phase_vocoder ola wsola linear].include?(method)

      signal = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      return apply_channels(signal) { |channel| time_stretch(channel, rate:, n_fft:, hop_length:, method:, phase_lock:, force_phase_vocoder:) } if signal.ndim == 2
      return signal if signal.empty? || rate == 1.0
      return linear_time_stretch(signal.to_a, rate) if method == :linear
      return ola_time_stretch(signal.to_a, rate) if %i[ola wsola].include?(method) || (!force_phase_vocoder && signal.size < MIN_PHASE_VOCODER_SAMPLES)

      n_fft ||= phase_vocoder_fft_size(signal.size)
      hop_length ||= [n_fft / 4, 1].max

      stft_matrix = Muze::Core::STFT.stft(signal, n_fft:, hop_length:, center: true)
      stretched_stft = phase_vocoder(stft_matrix, rate:, hop_length:, n_fft:, phase_lock:)
      target_length = [(signal.size / rate).round, 1].max

      Muze::Core::STFT.istft(stretched_stft, hop_length:, center: true, length: target_length)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param sr [Integer]
    # @param n_steps [Float]
    # @return [Numo::SFloat]
    def pitch_shift(y, sr: 22_050, n_steps: 0, bins_per_octave: 12, res_type: :auto, normalize: false, clip: nil)
      validate_positive_integer!(sr, "sr")
      validate_positive_number!(bins_per_octave, "bins_per_octave")
      raise Muze::ParameterError, "n_steps must be finite" unless n_steps.respond_to?(:finite?) && n_steps.finite?
      raise Muze::ParameterError, "normalize must be true or false" unless [true, false].include?(normalize)
      validate_positive_number!(clip, "clip") if clip

      signal = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      return apply_channels(signal) { |channel| pitch_shift(channel, sr:, n_steps:, bins_per_octave:, res_type:, normalize:, clip:) } if signal.ndim == 2
      return signal if n_steps.zero?

      rate = 2.0**(-n_steps.to_f / bins_per_octave)
      stretched = time_stretch(signal, rate:)
      effective_res_type = res_type == :auto ? (signal.size >= MIN_PHASE_VOCODER_SAMPLES ? :sinc : :linear) : res_type
      restored = resample_for_pitch_shift(stretched, target_size: signal.size, sr:, rate:, res_type: effective_res_type)
      output = Numo::SFloat.cast(restored[0...signal.size])
      output = normalize_peak(output) if normalize
      output = output.clip(-clip, clip) if clip
      output
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param top_db [Float]
    # @param frame_length [Integer]
    # @param hop_length [Integer]
    # @return [Array(Numo::SFloat, Array<Integer>)] trimmed signal and [start, end]
    def trim(y, top_db: 60, frame_length: 2048, hop_length: 512, ref: :max, aggregate: :mean)
      raise Muze::ParameterError, "top_db must be non-negative" if top_db.negative?
      raise Muze::ParameterError, "frame_length and hop_length must be positive" unless frame_length.positive? && hop_length.positive?
      raise Muze::ParameterError, "aggregate must be :mean or :max" unless %i[mean max].include?(aggregate)

      signal = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      amplitude = sample_amplitude(signal, aggregate:)
      frames = Muze::Core::Frames.slice(amplitude, frame_length:, hop_length:, pad_end: true)
      energies = frames.map do |frame|
        values = frame.map { |value| value * value }
        aggregate == :max ? Math.sqrt(values.max || 0.0) : Math.sqrt(values.sum(0.0) / frame.length)
      end
      reference = trim_reference(energies, ref:)
      threshold = [reference, 1.0e-12].max * (10.0**(-top_db / 20.0))
      active_frames = energies.each_index.select { |index| energies[index] >= threshold }
      return [Numo::SFloat[], [0, 0]] if active_frames.empty?

      search_start = active_frames.first * hop_length
      sample_count = amplitude.length
      search_end = [(active_frames.last * hop_length) + frame_length, sample_count].min
      active_samples = (search_start...search_end).select { |index| amplitude[index] >= threshold }
      empty = signal.ndim == 2 ? Numo::SFloat.zeros(0, signal.shape[1]) : Numo::SFloat[]
      return [empty, [0, 0]] if active_samples.empty?

      start_sample = active_samples.first
      end_sample = active_samples.last + 1
      trimmed = signal.ndim == 2 ? signal[start_sample...end_sample, true] : signal[start_sample...end_sample]
      [trimmed, [start_sample, end_sample]]
    end

    def preemphasis(y, coef: 0.97)
      validate_finite_number!(coef, "coef")
      matrix = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      return apply_channels(matrix) { |channel| preemphasis(channel, coef:) } if matrix.ndim == 2

      signal = matrix.to_a
      return Numo::SFloat.cast(signal) if signal.empty?

      output = Array.new(signal.length, 0.0)
      output[0] = signal[0]
      (1...signal.length).each { |index| output[index] = signal[index] - (coef * signal[index - 1]) }
      Numo::SFloat.cast(output)
    end

    def deemphasis(y, coef: 0.97)
      validate_finite_number!(coef, "coef")
      matrix = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      return apply_channels(matrix) { |channel| deemphasis(channel, coef:) } if matrix.ndim == 2

      signal = matrix.to_a
      return Numo::SFloat.cast(signal) if signal.empty?

      output = Array.new(signal.length, 0.0)
      output[0] = signal[0]
      (1...signal.length).each { |index| output[index] = signal[index] + (coef * output[index - 1]) }
      Numo::SFloat.cast(output)
    end

    # @param signal_length [Integer]
    # @return [Integer]
    def phase_vocoder_fft_size(signal_length)
      max_allowed = signal_length < MIN_PHASE_VOCODER_SAMPLES ? 512 : 2048
      max_fft = [signal_length, max_allowed].min
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
    def phase_vocoder(stft_matrix, rate:, hop_length:, n_fft:, phase_lock: false)
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

      phase_lock ? phase_lock_spectrum(stretched) : stretched
    end
    private_class_method :phase_vocoder

    def phase_lock_spectrum(stft_matrix)
      rows, cols = stft_matrix.shape
      output = stft_matrix.dup
      cols.times do |col|
        peak_bins = local_peak_bins(stft_matrix[true, col])
        next if peak_bins.empty?

        rows.times do |row|
          peak = peak_bins.min_by { |candidate| (candidate - row).abs }
          output[row, col] = Complex.polar(stft_matrix[row, col].abs, phase_of(stft_matrix[peak, col]))
        end
      end
      output
    end
    private_class_method :phase_lock_spectrum

    def local_peak_bins(spectrum)
      values = spectrum.abs.to_a
      (1...(values.length - 1)).select { |index| values[index] >= values[index - 1] && values[index] >= values[index + 1] }
    end
    private_class_method :local_peak_bins

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

    def ola_time_stretch(signal, rate)
      frame_length = [[next_power_of_two([signal.length / 8, 256].max), 2048].min, 32].max
      analysis_hop = [frame_length / 2, 1].max
      synthesis_hop = [(analysis_hop / rate).round, 1].max
      frame_count = signal.length <= frame_length ? 1 : (((signal.length - frame_length).to_f / analysis_hop).ceil + 1)
      target_length = [(signal.length / rate).round, 1].max
      output = Array.new(target_length + frame_length, 0.0)
      window_sums = Array.new(output.length, 0.0)
      window = Muze::Core::Windows.hann(frame_length).to_a

      frame_count.times do |frame_index|
        source_start = frame_index * analysis_hop
        target_start = frame_index * synthesis_hop
        frame_length.times do |offset|
          source_index = source_start + offset
          target_index = target_start + offset
          break if target_index >= output.length

          value = source_index < signal.length ? signal[source_index] : 0.0
          weight = window[offset]
          output[target_index] += value * weight
          window_sums[target_index] += weight * weight
        end
      end

      output.map!.with_index do |value, index|
        denominator = window_sums[index]
        denominator > 1.0e-12 ? value / denominator : value
      end
      Numo::SFloat.cast(output[0, target_length])
    end
    private_class_method :ola_time_stretch

    def next_power_of_two(value)
      power = 1
      power *= 2 while power < value
      power
    end
    private_class_method :next_power_of_two

    # Prefer sinc-quality resampling, then fall back to linear on failure.
    # @param stretched [Numo::SFloat]
    # @param target_size [Integer]
    # @param sr [Integer]
    # @param rate [Float]
    # @param res_type [Symbol]
    # @return [Numo::SFloat]
    def resample_for_pitch_shift(stretched, target_size:, sr:, rate:, res_type:)
      target_sr = [(sr * rate).round, 1].max
      Muze::Core::Resample.resample(stretched, orig_sr: sr, target_sr:, res_type:, target_length: target_size)
    rescue Muze::ParameterError
      Muze::Core::Resample.resample(stretched, orig_sr: stretched.size, target_sr: target_size, res_type: :linear, target_length: target_size)
    end
    private_class_method :resample_for_pitch_shift

    def trim_reference(energies, ref:)
      case ref
      when :max then energies.max || 0.0
      when Numeric then ref.to_f
      when Proc then ref.call(energies)
      else
        raise Muze::ParameterError, "ref must be :max, numeric, or a Proc"
      end
    end
    private_class_method :trim_reference

    def apply_channels(matrix)
      frames, channels = matrix.shape
      processed = channels.times.map { |channel| yield(matrix[true, channel]) }
      output_length = processed.map(&:size).max || frames
      output = Numo::SFloat.zeros(output_length, channels)
      channels.times do |channel|
        values = processed[channel]
        output[0...values.size, channel] = values
      end
      output
    end
    private_class_method :apply_channels

    def sample_amplitude(signal, aggregate:)
      return signal.abs.to_a unless signal.ndim == 2

      frames, channels = signal.shape
      Array.new(frames) do |frame|
        values = Array.new(channels) { |channel| signal[frame, channel].abs }
        aggregate == :max ? values.max : values.sum(0.0) / channels
      end
    end
    private_class_method :sample_amplitude

    def normalize_peak(signal)
      peak = signal.abs.max
      return signal if peak <= 0.0

      signal / peak
    end
    private_class_method :normalize_peak

    def validate_positive_integer!(value, label)
      return if value.is_a?(Integer) && value.positive?

      raise Muze::ParameterError, "#{label} must be a positive integer"
    end
    private_class_method :validate_positive_integer!

    def validate_optional_positive_integer!(value, label)
      return if value.nil?

      validate_positive_integer!(value, label)
    end
    private_class_method :validate_optional_positive_integer!

    def validate_positive_number!(value, label)
      return if value.respond_to?(:finite?) && value.finite? && value.positive?

      raise Muze::ParameterError, "#{label} must be positive"
    end
    private_class_method :validate_positive_number!

    def validate_finite_number!(value, label)
      return if value.respond_to?(:finite?) && value.finite?

      raise Muze::ParameterError, "#{label} must be finite"
    end
    private_class_method :validate_finite_number!
  end
end
