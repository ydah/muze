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
    # @param power [Float]
    # @param center [Boolean]
    # @param window [Symbol]
    # @param pad_mode [Symbol]
    # @param norm [Symbol, nil]
    # @return [Numo::SFloat]
    def melspectrogram(y: nil, sr: 22_050, s: nil, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil, power: 2.0, center: true, window: :hann, pad_mode: :reflect, norm: nil)
      raise Muze::ParameterError, "power must be positive" unless power.positive?

      spectrum = s ? Numo::SFloat.cast(s) : spectrogram(y, n_fft:, hop_length:, power:, center:, window:, pad_mode:)
      filter_bank = Muze::Filters.mel(sr:, n_fft:, n_mels:, fmin:, fmax:, norm:)
      Muze::Core::Matrix.multiply(filter_bank, spectrum)
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
    # @param dct_type [Integer]
    # @param lifter [Integer]
    # @param norm [Symbol, nil]
    # @return [Numo::SFloat]
    def mfcc(y: nil, sr: 22_050, s: nil, n_mfcc: 20, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil, dct_type: 2, lifter: 0, norm: :ortho)
      raise Muze::ParameterError, "n_mfcc must be positive" unless n_mfcc.positive?
      raise Muze::ParameterError, "lifter must be >= 0" if lifter.negative?

      mel_spec = if s
                   Numo::SFloat.cast(s)
                 else
                   melspectrogram(y:, sr:, n_fft:, hop_length:, n_mels:, fmin:, fmax:)
                 end

      log_mel = Muze.power_to_db(mel_spec)
      dct = Muze::Core::DCT.dct(log_mel, type: dct_type, axis: 0, norm:)
      coeffs = dct[0...n_mfcc, true].cast_to(Numo::SFloat)
      apply_lifter(coeffs, lifter:)
    end

    # @param data [Numo::SFloat]
    # @param order [Integer]
    # @param width [Integer]
    # @param mode [Symbol]
    # @return [Numo::SFloat]
      def delta(data, order: 1, width: 9, mode: :interp)
        raise Muze::ParameterError, "order must be >= 1" unless order >= 1
        raise Muze::ParameterError, "width must be odd and >= 3" unless width.odd? && width >= 3
      raise Muze::ParameterError, "mode must be :interp, :nearest, :mirror, or :constant" unless %i[interp nearest mirror constant].include?(mode)

      result = Numo::SFloat.cast(data)
      original_ndim = result.ndim
      order.times { result = finite_difference(result, width, mode:) }
      result = result[true, 0] if original_ndim == 1 && result.ndim == 2
      result
    end

    def spectrogram(y, n_fft:, hop_length:, power:, center:, window:, pad_mode:)
      raise Muze::ParameterError, "y must be provided when s is nil" if y.nil?

      stft_matrix = Muze.stft(y, n_fft:, hop_length:, center:, window:, pad_mode:)
      magnitude, = Muze.magphase(stft_matrix)
      (magnitude**power).cast_to(Numo::SFloat)
    end
    private_class_method :spectrogram

    def finite_difference(data, width, mode:)
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
            left = sample_with_mode(matrix, row, col - offset, cols, mode:)
            right = sample_with_mode(matrix, row, col + offset, cols, mode:)
            numerator += offset * (right - left)
          end
          output[row, col] = numerator / denominator
        end
      end

      output
    end
    private_class_method :finite_difference

    def sample_with_mode(matrix, row, col, cols, mode:)
      return matrix[row, col] if col.between?(0, cols - 1)

      case mode
      when :constant
        0.0
      when :mirror
        matrix[row, mirror_index(col, cols)]
      else
        matrix[row, [[col, 0].max, cols - 1].min]
      end
    end
    private_class_method :sample_with_mode

    def mirror_index(index, length)
      return 0 if length <= 1

      period = (length - 1) * 2
      mirrored = index % period
      mirrored >= length ? period - mirrored : mirrored
    end
    private_class_method :mirror_index

    def apply_lifter(coeffs, lifter:)
      return coeffs if lifter.zero?

      rows, = coeffs.shape
      rows.times do |index|
        coeffs[index, true] = coeffs[index, true] * (1.0 + ((lifter / 2.0) * Math.sin(Math::PI * (index + 1) / lifter)))
      end
      coeffs
    end
    private_class_method :apply_lifter
  end
end
