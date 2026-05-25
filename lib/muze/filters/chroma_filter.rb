# frozen_string_literal: true

module Muze
  module Filters
    module_function
    CHROMA_CACHE = {}

    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param n_chroma [Integer]
    # @param tuning [Float]
    # @return [Numo::SFloat] shape: [n_chroma, 1 + n_fft/2]
    def chroma(sr:, n_fft:, n_chroma: 12, tuning: 0.0)
      key = [sr, n_fft, n_chroma, tuning]
      (CHROMA_CACHE[key] ||= build_chroma(sr:, n_fft:, n_chroma:, tuning:)).dup
    end

    def build_chroma(sr:, n_fft:, n_chroma:, tuning:)
      raise Muze::ParameterError, "sr must be positive" unless sr.positive?
      raise Muze::ParameterError, "n_fft must be positive" unless n_fft.positive?
      raise Muze::ParameterError, "n_chroma must be positive" unless n_chroma.positive?
      raise Muze::ParameterError, "tuning must be finite" unless tuning.respond_to?(:finite?) && tuning.finite?

      bins = (n_fft / 2) + 1
      matrix = Numo::SFloat.zeros(n_chroma, bins)

      bins.times do |bin|
        frequency = (bin * sr.to_f) / n_fft
        next if frequency <= 0.0

        midi = 69.0 + (12.0 * Math.log2(frequency / 440.0)) - tuning
        chroma_position = midi % n_chroma

        n_chroma.times do |chroma_index|
          distance = circular_distance(chroma_index, chroma_position, n_chroma)
          matrix[chroma_index, bin] = Math.exp(-(distance**2) / 2.0)
        end
      end

      normalize_columns(matrix)
    end
    private_class_method :build_chroma

    def circular_distance(a, b, modulo)
      direct = (a - b).abs
      [direct, modulo - direct].min
    end
    private_class_method :circular_distance

    def normalize_columns(matrix)
      cols = matrix.shape[1]
      cols.times do |col|
        sum = matrix[true, col].sum
        next if sum <= 0.0

        matrix[true, col] = matrix[true, col] / sum
      end
      matrix
    end
    private_class_method :normalize_columns
  end
end
