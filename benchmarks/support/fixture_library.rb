# frozen_string_literal: true

module Muze
  module Benchmarks
    # Fixture signal builder for quality/performance benchmark runs.
    module FixtureLibrary
      module_function

      # @param sample_rate [Integer]
      # @param duration [Float]
      # @return [Hash{String => Numo::SFloat}]
      def build(sample_rate: 22_050, duration: 1.0)
        sample_count = [(sample_rate * duration).round, 1].max

        sine = sine_wave(
          sample_rate: sample_rate,
          sample_count: sample_count,
          frequency: 440.0,
          amplitude: 0.8
        )
        click = click_track(
          sample_rate: sample_rate,
          sample_count: sample_count,
          interval_seconds: 0.1
        )
        simple_mix = mixed_signal(sample_rate:, sample_count:)

        {
          "sine" => Numo::SFloat.cast(sine),
          "click" => Numo::SFloat.cast(click),
          "simple_mix" => Numo::SFloat.cast(simple_mix)
        }
      end

      # @param sample_rate [Integer]
      # @param sample_count [Integer]
      # @param frequency [Float]
      # @param amplitude [Float]
      # @return [Array<Float>]
      def sine_wave(sample_rate:, sample_count:, frequency:, amplitude:)
        Array.new(sample_count) do |index|
          angle = (2.0 * Math::PI * frequency * index) / sample_rate
          amplitude * Math.sin(angle)
        end
      end
      private_class_method :sine_wave

      # @param sample_rate [Integer]
      # @param sample_count [Integer]
      # @param interval_seconds [Float]
      # @return [Array<Float>]
      def click_track(sample_rate:, sample_count:, interval_seconds:)
        click_interval = [(sample_rate * interval_seconds).round, 1].max
        signal = Array.new(sample_count, 0.0)

        index = 0
        while index < sample_count
          signal[index] = 0.95
          index += click_interval
        end

        signal
      end
      private_class_method :click_track

      # @param sample_rate [Integer]
      # @param sample_count [Integer]
      # @return [Array<Float>]
      def mixed_signal(sample_rate:, sample_count:)
        low = sine_wave(
          sample_rate: sample_rate,
          sample_count: sample_count,
          frequency: 220.0,
          amplitude: 0.5
        )
        high = sine_wave(
          sample_rate: sample_rate,
          sample_count: sample_count,
          frequency: 880.0,
          amplitude: 0.35
        )
        clicks = click_track(
          sample_rate: sample_rate,
          sample_count: sample_count,
          interval_seconds: 0.2
        )

        normalize_peak(
          low.each_with_index.map { |sample, index| sample + high[index] + (0.25 * clicks[index]) }
        )
      end
      private_class_method :mixed_signal

      # @param signal [Array<Float>]
      # @param target_peak [Float]
      # @return [Array<Float>]
      def normalize_peak(signal, target_peak: 0.9)
        peak = signal.map(&:abs).max.to_f
        return signal if peak <= 0.0

        scale = target_peak / peak
        signal.map { |sample| sample * scale }
      end
      private_class_method :normalize_peak
    end
  end
end
