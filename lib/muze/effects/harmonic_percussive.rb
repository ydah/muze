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
    def hpss(y, kernel_size: 31, power: 2.0, margin: 1.0, n_fft: 2048, hop_length: 512)
      stft_matrix = Muze.stft(y, n_fft:, hop_length:)
      magnitude, = Muze.magphase(stft_matrix)

      harmonic_median = median_filter(magnitude, kernel_size, axis: 1)
      percussive_median = median_filter(magnitude, kernel_size, axis: 0)

      harmonic_weight = harmonic_median**power
      percussive_weight = percussive_median**power

      harmonic_mask = harmonic_weight / (harmonic_weight + (margin * percussive_weight) + 1.0e-12)
      percussive_mask = percussive_weight / (percussive_weight + (margin * harmonic_weight) + 1.0e-12)

      harmonic_stft = stft_matrix * harmonic_mask
      percussive_stft = stft_matrix * percussive_mask

      signal = y.is_a?(Numo::NArray) ? y : Numo::SFloat.cast(y)
      harmonic = Muze.istft(harmonic_stft, hop_length:, length: signal.size)
      percussive = Muze.istft(percussive_stft, hop_length:, length: signal.size)
      [harmonic, percussive]
    end

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

          output[row, col] = values.sort[values.length / 2]
        end
      end

      output
    end
    private_class_method :median_filter
  end
end
