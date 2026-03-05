# frozen_string_literal: true

require_relative "audio_loader/wavify_backend"
require_relative "audio_loader/ffmpeg_backend"

module Muze
  module IO
    # Audio file loader with mono mixdown and optional resampling.
    module AudioLoader
      module_function

      SUPPORTED_FORMATS = %w[wav flac mp3 ogg].freeze

      # @param path [String]
      # @param sr [Integer] destination sample rate
      # @param mono [Boolean]
      # @param offset [Float] seconds from start
      # @param duration [Float, nil] duration in seconds
      # @return [Array(Numo::SFloat, Integer)] waveform and sample rate
      def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil)
        validate_args!(sr:, offset:, duration:)
        raise Muze::AudioLoadError, "File not found: #{path}" unless File.exist?(path)

        backend = select_backend(path)
        raw_samples, source_sr, _channels = backend.read(path)
        sliced = slice_by_time(raw_samples, source_sr, offset:, duration:)

        signal = if mono
                   downmix_to_mono(sliced)
                 else
                   sliced
                 end

        resampled = resample(signal, source_sr, sr)
        [Numo::SFloat.cast(resampled), sr]
      rescue Muze::AudioLoadError
        raise
      rescue Muze::UnsupportedFormatError, Muze::DependencyError => e
        raise Muze::AudioLoadError, e.message
      rescue StandardError => e
        raise Muze::AudioLoadError, "Failed to load #{path}: #{e.message}"
      end

      def validate_args!(sr:, offset:, duration:)
        raise Muze::ParameterError, "sr must be positive" unless sr.is_a?(Integer) && sr.positive?
        raise Muze::ParameterError, "offset must be >= 0" if offset.negative?
        return if duration.nil? || duration.positive?

        raise Muze::ParameterError, "duration must be positive"
      end
      private_class_method :validate_args!

      def select_backend(path)
        extension = File.extname(path).downcase

        if WavifyBackend.supported_extension?(extension)
          WavifyBackend
        elsif FFMPEGBackend.supported_extension?(extension)
          raise Muze::DependencyError, FFMPEGBackend.installation_message(extension) unless FFMPEGBackend.available?

          FFMPEGBackend
        else
          raise Muze::UnsupportedFormatError, unsupported_format_message(extension)
        end
      end
      private_class_method :select_backend

      def unsupported_format_message(extension)
        label = extension.empty? ? "(no extension)" : extension.delete_prefix(".")
        "Unsupported audio format: #{label}. Supported formats: #{SUPPORTED_FORMATS.join(', ')}"
      end
      private_class_method :unsupported_format_message

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
