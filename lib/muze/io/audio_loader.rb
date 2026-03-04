# frozen_string_literal: true

require "wavefile"

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
      rescue WaveFile::InvalidFormatError, StandardError => e
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
        samples = []
        source_sr = nil

        WaveFile::Reader.new(path) do |reader|
          source_sr = reader.native_format.sample_rate
          channels = reader.native_format.channels
          scale = pcm_scale(reader.native_format)

          reader.each_buffer(2048) do |buffer|
            buffer.samples.each do |sample|
              samples << normalize_frame(sample, channels, scale)
            end
          end
        end

        [samples, source_sr]
      end
      private_class_method :read_wave

      def pcm_scale(format)
        case format.sample_format
        when :pcm_8 then 128.0
        when :pcm_16 then 32_768.0
        when :pcm_24 then 8_388_608.0
        when :pcm_32 then 2_147_483_648.0
        else
          pcm_from_bit_depth(format)
        end
      end
      private_class_method :pcm_scale

      def pcm_from_bit_depth(format)
        return 1.0 unless format.audio_format == 1 && format.bits_per_sample.to_i.positive?

        (2**(format.bits_per_sample - 1)).to_f
      end
      private_class_method :pcm_from_bit_depth

      def normalize_frame(sample, channels, scale)
        if channels == 1
          normalize_value(sample, scale)
        elsif sample.is_a?(Array)
          sample.map { |value| normalize_value(value, scale) }
        else
          Array(sample).map { |value| normalize_value(value, scale) }
        end
      end
      private_class_method :normalize_frame

      def normalize_value(value, scale)
        return value.to_f if scale == 1.0

        value.to_f / scale
      end
      private_class_method :normalize_value

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
