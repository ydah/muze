# frozen_string_literal: true

require_relative "audio_loader/wavify_backend"
require_relative "audio_loader/ffmpeg_backend"

module Muze
  module IO
    # Audio file loader with mono mixdown and optional resampling.
    module AudioLoader
      module_function

      BACKENDS = [
        WavifyBackend,
        FFMPEGBackend
      ].freeze
      SUPPORTED_FORMATS = BACKENDS.flat_map { |backend| backend::SUPPORTED_EXTENSIONS }.map { |ext| ext.delete_prefix(".") }.sort.freeze

      # @param path [String, Pathname]
      # @param sr [Integer, nil] destination sample rate; nil preserves source rate
      # @param mono [Boolean, Symbol]
      # @param offset [Float] seconds from start
      # @param duration [Float, nil] duration in seconds
      # @param dtype [Class, Symbol]
      # @param normalize [Boolean]
      # @return [Array(Numo::SFloat, Integer)] waveform and sample rate
      def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil, dtype: Numo::SFloat, normalize: false)
        resolved_path = resolve_path(path)
        validate_args!(sr:, mono:, offset:, duration:, dtype:, normalize:)
        raise Muze::AudioLoadError, "File not found: #{resolved_path}" unless File.exist?(resolved_path)

        backend = select_backend(resolved_path)
        raw_samples, source_sr, _channels = backend.read(resolved_path, offset:, duration:)
        sliced = backend.applies_time_window? ? raw_samples : slice_by_time(raw_samples, source_sr, offset:, duration:)

        signal = downmix(sliced, mono:)
        target_sr = sr || source_sr

        resampled = resample(signal, source_sr, target_sr)
        output = cast_signal(resampled, dtype)
        output = normalize_signal(output) if normalize
        [output, target_sr]
      rescue Muze::AudioLoadError, Muze::ParameterError
        raise
      rescue Muze::UnsupportedFormatError, Muze::DependencyError => e
        raise Muze::AudioLoadError, e.message
      rescue StandardError => e
        raise Muze::AudioLoadError, "Failed to load #{path}: #{e.message}"
      end

      # @param path [String, Pathname]
      # @return [Hash]
      def info(path)
        resolved_path = resolve_path(path)
        raise Muze::AudioLoadError, "File not found: #{resolved_path}" unless File.exist?(resolved_path)

        select_backend(resolved_path).info(resolved_path)
      rescue Muze::AudioLoadError
        raise
      rescue Muze::UnsupportedFormatError, Muze::DependencyError => e
        raise Muze::AudioLoadError, e.message
      rescue StandardError => e
        raise Muze::AudioLoadError, "Failed to inspect #{path}: #{e.message}"
      end

      def resolve_path(path)
        resolved = path.respond_to?(:to_path) ? path.to_path : path
        return resolved.to_s if resolved.is_a?(String)

        raise Muze::AudioLoadError, "Audio path must be a String or Pathname"
      end
      private_class_method :resolve_path

      def validate_args!(sr:, mono:, offset:, duration:, dtype:, normalize:)
        raise Muze::ParameterError, "sr must be positive or nil" unless sr.nil? || (sr.is_a?(Integer) && sr.positive?)
        raise Muze::ParameterError, "mono must be true, false, :mean, :left, or :right" unless [true, false, :mean, :left, :right].include?(mono)
        raise Muze::ParameterError, "offset must be >= 0" if offset.negative?
        raise Muze::ParameterError, "normalize must be true or false" unless [true, false].include?(normalize)
        dtype_class(dtype)
        return if duration.nil? || duration.positive?

        raise Muze::ParameterError, "duration must be positive"
      end
      private_class_method :validate_args!

      def select_backend(path)
        extension = File.extname(path).downcase
        backend = BACKENDS.find { |candidate| candidate.supported_extension?(extension) }

        raise Muze::UnsupportedFormatError, unsupported_format_message(extension) unless backend
        raise Muze::DependencyError, backend.installation_message(extension) unless backend.available?

        backend
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

      def downmix(samples, mono:)
        return samples if mono == false
        return downmix_to_mono(samples) if mono == true || mono == :mean
        return samples unless samples.first.is_a?(Array)

        channel_index = mono == :left ? 0 : samples.first.length - 1
        samples.map { |frame| frame.fetch(channel_index) }
      end
      private_class_method :downmix

      def downmix_to_mono(samples)
        return samples if samples.empty?
        return samples unless samples.first.is_a?(Array)

        samples.map { |frame| frame.sum(0.0) / frame.length }
      end
      private_class_method :downmix_to_mono

      def resample(samples, source_sr, target_sr)
        return [] if samples.empty?

        Muze::Core::Resample.resample(samples, orig_sr: source_sr, target_sr: target_sr, res_type: :sinc)
      end
      private_class_method :resample

      def cast_signal(signal, dtype)
        dtype_class(dtype).cast(signal)
      end
      private_class_method :cast_signal

      def dtype_class(dtype)
        case dtype
        when :sfloat, :float32 then Numo::SFloat
        when :dfloat, :float64 then Numo::DFloat
        else
          return Numo::SFloat if dtype == Numo::SFloat
          return Numo::DFloat if dtype == Numo::DFloat

          raise Muze::ParameterError, "dtype must be :sfloat, :float32, :dfloat, :float64, Numo::SFloat, or Numo::DFloat"
        end
      end
      private_class_method :dtype_class

      def normalize_signal(signal)
        peak = signal.abs.max
        return signal if peak <= 0.0

        (signal / peak).cast_to(signal.class)
      end
      private_class_method :normalize_signal
    end
  end
end
