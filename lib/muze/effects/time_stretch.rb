# frozen_string_literal: true

module Muze
  module Effects
    module_function

    # @param y [Numo::SFloat, Array<Float>]
    # @param rate [Float]
    # @return [Numo::SFloat]
    def time_stretch(y, rate: 1.0)
      raise Muze::ParameterError, "rate must be positive" unless rate.positive?

      signal = y.is_a?(Numo::NArray) ? y.to_a : Array(y)
      return Numo::SFloat.cast(signal) if signal.empty? || rate == 1.0

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
      restored = Muze::Core::Resample.resample(stretched, orig_sr: stretched.size, target_sr: signal.size, res_type: :linear)
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
  end
end
