# frozen_string_literal: true

require "wavify"

module Muze
  module IO
    # WAV file loader with mono mixdown and optional resampling.
    module AudioLoader
      module_function

      # @param path [String]
      # @param sr [Integer] destination sample rate
      # @param mono [Boolean]
      # @param offset [Float] seconds from start
      # @param duration [Float, nil] duration in seconds
      # @return [Array(Numo::SFloat, Integer)] waveform and sample rate
      def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil)
        validate_args!(sr:, offset:, duration:)
        raise Muze::AudioLoadError, "File not found: #{path}" unless File.exist?(path)

        raw_samples, source_sr = read_wave(path)
        sliced = slice_by_time(raw_samples, source_sr, offset:, duration:)

        signal = if mono
                   downmix_to_mono(sliced)
                 else
                   sliced
                 end

        resampled = resample(signal, source_sr, sr)
        [Numo::SFloat.cast(resampled), sr]
      rescue Wavify::Error, StandardError => e
        raise if e.is_a?(Muze::AudioLoadError)

        raise Muze::AudioLoadError, "Failed to load #{path}: #{e.message}"
      end

      def validate_args!(sr:, offset:, duration:)
        raise Muze::ParameterError, "sr must be positive" unless sr.is_a?(Integer) && sr.positive?
        raise Muze::ParameterError, "offset must be >= 0" if offset.negative?
        return if duration.nil? || duration.positive?

        raise Muze::ParameterError, "duration must be positive"
      end
      private_class_method :validate_args!

      def read_wave(path)
        audio = Wavify::Audio.read(path)
        float_format = audio.format.with(sample_format: :float, bit_depth: 32)
        converted = audio.convert(float_format)

        [samples_from_buffer(converted.buffer), converted.format.sample_rate]
      end
      private_class_method :read_wave

      def samples_from_buffer(buffer)
        return buffer.samples if buffer.format.channels == 1

        buffer.samples.each_slice(buffer.format.channels).map(&:dup)
      end
      private_class_method :samples_from_buffer

      def slice_by_time(samples, sample_rate, offset:, duration:)
        start_index = (offset * sample_rate).floor
        return [] if start_index >= samples.length

        end_index = if duration
                      start_index + (duration * sample_rate).floor
                    else
                      samples.length
                    end

        samples[start_index...[end_index, samples.length].min] || []
      end
      private_class_method :slice_by_time

      def downmix_to_mono(samples)
        return samples if samples.empty?
        return samples unless samples.first.is_a?(Array)

        samples.map { |frame| frame.sum(0.0) / frame.length }
      end
      private_class_method :downmix_to_mono

      def resample(samples, source_sr, target_sr)
        if samples.empty?
          []
        elsif samples.first.is_a?(Array)
          channel_count = samples.first.length
          channels = Array.new(channel_count) { [] }
          samples.each { |frame| frame.each_with_index { |sample, index| channels[index] << sample } }

          resampled_channels = channels.map do |channel_data|
            Muze::Core::Resample.resample(channel_data, orig_sr: source_sr, target_sr: target_sr, res_type: :sinc).to_a
          end

          target_length = resampled_channels.first.length
          Array.new(target_length) { |idx| resampled_channels.map { |channel| channel[idx] } }
        else
          Muze::Core::Resample.resample(samples, orig_sr: source_sr, target_sr: target_sr, res_type: :sinc).to_a
        end
      end
      private_class_method :resample
    end
  end
end
