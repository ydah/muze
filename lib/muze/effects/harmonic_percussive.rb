# frozen_string_literal: true

module Muze
  module Effects
    module_function

    # @param y [Numo::SFloat, Array<Float>]
    # @param kernel_size [Integer]
    # @param power [Float]
    # @param margin [Float]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @return [Array(Numo::SFloat, Numo::SFloat)] harmonic and percussive waveforms
    def hpss(y, kernel_size: 31, power: 2.0, margin: 1.0, n_fft: 2048, hop_length: 512, return_masks: false)
      validate_hpss_params!(kernel_size:, power:, margin:)
      raise Muze::ParameterError, "return_masks must be true or false" unless [true, false].include?(return_masks)

      signal = Muze::Core::Audio.validate_audio!(y, allow_empty: true)
      return hpss_channels(signal, kernel_size:, power:, margin:, n_fft:, hop_length:, return_masks:) if signal.ndim == 2

      hpss_mono(signal, kernel_size:, power:, margin:, n_fft:, hop_length:, return_masks:)
    end

    def hpss_mono(signal, kernel_size:, power:, margin:, n_fft:, hop_length:, return_masks:)
      signal = Numo::SFloat.cast(signal)

      stft_matrix = Muze.stft(signal, n_fft:, hop_length:)
      magnitude, = Muze.magphase(stft_matrix)

      harmonic_median = median_filter(magnitude, kernel_size, axis: 1)
      percussive_median = median_filter(magnitude, kernel_size, axis: 0)

      harmonic_weight = harmonic_median**power
      percussive_weight = percussive_median**power
      harmonic_margin, percussive_margin = Array(margin)
      harmonic_margin ||= margin
      percussive_margin ||= harmonic_margin

      harmonic_mask = soft_mask(harmonic_weight, harmonic_weight + (harmonic_margin * percussive_weight), power: 1.0)
      percussive_mask = soft_mask(percussive_weight, percussive_weight + (percussive_margin * harmonic_weight), power: 1.0)

      harmonic_stft = stft_matrix * harmonic_mask
      percussive_stft = stft_matrix * percussive_mask

      harmonic = Muze.istft(harmonic_stft, hop_length:, length: signal.size)
      percussive = Muze.istft(percussive_stft, hop_length:, length: signal.size)
      return [harmonic, percussive, harmonic_mask, percussive_mask] if return_masks

      [harmonic, percussive]
    end
    private_class_method :hpss_mono

    def hpss_channels(signal, kernel_size:, power:, margin:, n_fft:, hop_length:, return_masks:)
      frames, channels = signal.shape
      harmonic = Numo::SFloat.zeros(frames, channels)
      percussive = Numo::SFloat.zeros(frames, channels)
      harmonic_masks = []
      percussive_masks = []

      channels.times do |channel|
        result = hpss_mono(
          signal[true, channel],
          kernel_size:,
          power:,
          margin:,
          n_fft:,
          hop_length:,
          return_masks: true
        )
        harmonic[true, channel] = result[0]
        percussive[true, channel] = result[1]
        harmonic_masks << result[2]
        percussive_masks << result[3]
      end

      return [harmonic, percussive, harmonic_masks, percussive_masks] if return_masks

      [harmonic, percussive]
    end
    private_class_method :hpss_channels

    def validate_hpss_params!(kernel_size:, power:, margin:)
      raise Muze::ParameterError, "kernel_size must be a positive odd integer" unless kernel_size.is_a?(Integer) && kernel_size.positive? && kernel_size.odd?
      raise Muze::ParameterError, "power must be positive" unless power.positive?

      margins = Array(margin)
      raise Muze::ParameterError, "margin must be positive or [harmonic_margin, percussive_margin]" unless [1, 2].include?(margins.length)
      return if margins.all? { |value| value.respond_to?(:positive?) && value.positive? }

      raise Muze::ParameterError, "margin must be positive"
    end
    private_class_method :validate_hpss_params!

    def soft_mask(numerator, denominator, power:)
      powered_numerator = numerator**power
      powered_denominator = denominator**power
      powered_numerator / (powered_denominator + 1.0e-12)
    end
    private_class_method :soft_mask

    def median_filter(matrix, kernel_size, axis:)
      half = kernel_size / 2
      rows, cols = matrix.shape
      output = Numo::SFloat.zeros(rows, cols)

      rows.times do |row|
        cols.times do |col|
          values = []
          if axis == 1
            start_col = [col - half, 0].max
            end_col = [col + half, cols - 1].min
            (start_col..end_col).each { |index| values << matrix[row, index] }
          else
            start_row = [row - half, 0].max
            end_row = [row + half, rows - 1].min
            (start_row..end_row).each { |index| values << matrix[index, col] }
          end

          output[row, col] = Muze::Native.median1d(values)
        end
      end

      output
    end
    private_class_method :median_filter
  end
end
