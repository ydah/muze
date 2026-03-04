# frozen_string_literal: true

module Muze
  # Feature extraction methods.
  module Feature
    module_function

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @return [Numo::SFloat]
    def melspectrogram(y: nil, sr: 22_050, s: nil, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil)
      power_spectrum = s ? Numo::SFloat.cast(s) : power_spectrogram(y, n_fft:, hop_length:)
      filter_bank = Muze::Filters.mel(sr:, n_fft:, n_mels:, fmin:, fmax:)
      matrix_multiply(filter_bank, power_spectrum)
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param n_mfcc [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @return [Numo::SFloat]
    def mfcc(y: nil, sr: 22_050, s: nil, n_mfcc: 20, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil)
      raise Muze::ParameterError, "n_mfcc must be positive" unless n_mfcc.positive?

      mel_spec = if s
                   Numo::SFloat.cast(s)
                 else
                   melspectrogram(y:, sr:, n_fft:, hop_length:, n_mels:, fmin:, fmax:)
                 end

      log_mel = Muze.power_to_db(mel_spec)
      dct = Muze::Core::DCT.dct(log_mel, axis: 0, norm: :ortho)
      dct[0...n_mfcc, true].cast_to(Numo::SFloat)
    end

    # @param data [Numo::SFloat]
    # @param order [Integer]
    # @param width [Integer]
    # @param mode [Symbol]
    # @return [Numo::SFloat]
    def delta(data, order: 1, width: 9, mode: :interp)
      raise Muze::ParameterError, "order must be >= 1" unless order >= 1
      raise Muze::ParameterError, "width must be odd and >= 3" unless width.odd? && width >= 3
      raise Muze::ParameterError, "mode must be :interp" unless mode == :interp

      result = Numo::SFloat.cast(data)
      order.times { result = finite_difference(result, width) }
      result
    end

    def power_spectrogram(y, n_fft:, hop_length:)
      raise Muze::ParameterError, "y must be provided when s is nil" if y.nil?

      stft_matrix = Muze.stft(y, n_fft:, hop_length:)
      magnitude, = Muze.magphase(stft_matrix)
      (magnitude**2).cast_to(Numo::SFloat)
    end
    private_class_method :power_spectrogram

    def finite_difference(data, width)
      matrix = Numo::SFloat.cast(data)
      matrix = matrix.expand_dims(1) if matrix.ndim == 1

      rows, cols = matrix.shape
      half = width / 2
      denominator = (1..half).sum { |idx| 2.0 * (idx * idx) }
      output = Numo::SFloat.zeros(rows, cols)

      rows.times do |row|
        cols.times do |col|
          numerator = 0.0
          (1..half).each do |offset|
            left = [[col - offset, 0].max, cols - 1].min
            right = [[col + offset, 0].max, cols - 1].min
            numerator += offset * (matrix[row, right] - matrix[row, left])
          end
          output[row, col] = numerator / denominator
        end
      end

      data.ndim == 1 ? output[true, 0] : output
    end
    private_class_method :finite_difference

    def matrix_multiply(left, right)
      left_matrix = Numo::SFloat.cast(left)
      right_matrix = Numo::SFloat.cast(right)
      left_matrix = left_matrix.expand_dims(1) if left_matrix.ndim == 1
      right_matrix = right_matrix.expand_dims(1) if right_matrix.ndim == 1

      left_rows, left_cols = left_matrix.shape
      right_rows, right_cols = right_matrix.shape
      raise Muze::ParameterError, "Matrix dimensions do not align" unless left_cols == right_rows

      output = Numo::SFloat.zeros(left_rows, right_cols)

      left_rows.times do |row|
        right_cols.times do |col|
          sum = 0.0
          left_cols.times { |idx| sum += left_matrix[row, idx] * right_matrix[idx, col] }
          output[row, col] = sum
        end
      end

      output
    end
    private_class_method :matrix_multiply
  end
end
