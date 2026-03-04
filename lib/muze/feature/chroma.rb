# frozen_string_literal: true

module Muze
  module Feature
    module_function

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param n_chroma [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param norm [Integer, nil]
    # @return [Numo::SFloat] shape: [n_chroma, frames]
    def chroma_stft(y: nil, sr: 22_050, s: nil, n_chroma: 12, n_fft: 2048, hop_length: 512, norm: 2)
      spectrum = if s
                   Numo::SFloat.cast(s)
                 else
                   stft_matrix = Muze.stft(y, n_fft:, hop_length:)
                   magnitude, = Muze.magphase(stft_matrix)
                   magnitude
                 end

      spectrum = spectrum.expand_dims(1) if spectrum.ndim == 1
      filter_bank = Muze::Filters.chroma(sr:, n_fft:, n_chroma:)
      chroma = matrix_multiply(filter_bank, spectrum)
      normalize(chroma, norm:)
    end

    def matrix_multiply(left, right)
      left_rows, left_cols = left.shape
      right_rows, right_cols = right.shape
      raise Muze::ParameterError, "Matrix dimensions do not align" unless left_cols == right_rows

      output = Numo::SFloat.zeros(left_rows, right_cols)
      left_rows.times do |row|
        right_cols.times do |col|
          sum = 0.0
          left_cols.times { |idx| sum += left[row, idx] * right[idx, col] }
          output[row, col] = sum
        end
      end

      output
    end
    private_class_method :matrix_multiply

    def normalize(chroma, norm:)
      return chroma if norm.nil?

      frames = chroma.shape[1]
      frames.times do |frame_index|
        vector = chroma[true, frame_index]
        denominator = if norm == 1
                        vector.abs.sum
                      else
                        Math.sqrt((vector**2).sum)
                      end

        next if denominator <= 1.0e-12

        chroma[true, frame_index] = vector / denominator
      end
      chroma
    end
    private_class_method :normalize
  end
end
