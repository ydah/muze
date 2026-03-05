# frozen_string_literal: true

module SpecEffectQualityMetrics
  module_function

  # @param y [Numo::SFloat, Array<Float>]
  # @param sr [Integer]
  # @param n_fft [Integer]
  # @return [Float]
  def dominant_frequency(y, sr:, n_fft: 2048)
    stft_matrix = Muze.stft(y, n_fft:, hop_length: 256)
    magnitude, = Muze.magphase(stft_matrix)
    averaged = magnitude.mean(1).to_a
    peak_bin = averaged.each_with_index.max_by { |value, _index| value }[1]

    peak_bin * sr.to_f / n_fft
  end

  # @param y [Numo::SFloat, Array<Float>]
  # @param sr [Integer]
  # @param count [Integer]
  # @param n_fft [Integer]
  # @return [Array<Float>]
  def top_frequencies(y, sr:, count: 2, n_fft: 4096)
    stft_matrix = Muze.stft(y, n_fft:, hop_length: 256)
    magnitude, = Muze.magphase(stft_matrix)
    averaged = magnitude.mean(1).to_a
    top_bins = averaged.each_with_index.max_by(count) { |value, _index| value }.map(&:last)

    top_bins.map { |bin| bin * sr.to_f / n_fft }
  end

  # @param y [Numo::SFloat, Array<Float>]
  # @param threshold [Float]
  # @param min_distance [Integer]
  # @return [Array<Integer>]
  def click_positions(y, threshold: 0.5, min_distance: 512)
    samples = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
    positions = []
    last_position = -min_distance

    samples.each_with_index do |sample, index|
      next if sample.abs < threshold
      next if (index - last_position) < min_distance

      positions << index
      last_position = index
    end

    positions
  end
end
