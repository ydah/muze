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

      # @param path [String, Pathname, IO]
      # @param sr [Integer, nil] destination sample rate; nil preserves source rate
      # @param mono [Boolean, Symbol]
      # @param offset [Float] seconds from start
      # @param duration [Float, nil] duration in seconds
      # @param dtype [Class, Symbol]
      # @param normalize [Boolean]
      # @param format [Symbol, String, nil]
      # @param weights [Array<Float>, nil]
      # @param max_bytes [Integer, nil]
      # @return [Array(Numo::SFloat, Integer)] waveform and sample rate
      def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil, dtype: Numo::SFloat, normalize: false, format: nil, weights: nil, max_bytes: nil)
        source = resolve_source(path, format:)
        validate_args!(sr:, mono:, offset:, duration:, dtype:, normalize:, weights:, max_bytes:)
        validate_source_size!(source, max_bytes:)

        backend = select_backend(source)
        raw_samples, source_sr, _channels = backend.read(source.fetch(:input), offset:, duration:)
        sliced = backend.applies_time_window? ? raw_samples : slice_by_time(raw_samples, source_sr, offset:, duration:)

        signal = downmix(sliced, mono:, weights:)
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

      # @param path [String, Pathname, IO]
      # @return [Hash]
      def info(path, format: nil)
        source = resolve_source(path, format:)

        select_backend(source).info(source.fetch(:input))
      rescue Muze::AudioLoadError
        raise
      rescue Muze::UnsupportedFormatError, Muze::DependencyError => e
        raise Muze::AudioLoadError, e.message
      rescue StandardError => e
        raise Muze::AudioLoadError, "Failed to inspect #{path}: #{e.message}"
      end

      def resolve_source(path, format:)
        resolved = path.respond_to?(:to_path) ? path.to_path : path
        if resolved.is_a?(String)
          raise Muze::AudioLoadError, "File not found: #{resolved}" unless File.exist?(resolved)

          return { input: resolved, extension: normalized_extension(format || File.extname(resolved)), path?: true }
        end

        return { input: resolved, extension: normalized_extension(format || :wav), path?: false } if resolved.respond_to?(:read)

        raise Muze::AudioLoadError, "Audio source must be a String, Pathname, or IO-like object"
      end
      private_class_method :resolve_source

      def normalized_extension(format)
        extension = format.to_s
        extension = ".#{extension}" unless extension.start_with?(".")
        extension.downcase
      end
      private_class_method :normalized_extension

      def validate_args!(sr:, mono:, offset:, duration:, dtype:, normalize:, weights:, max_bytes:)
        raise Muze::ParameterError, "sr must be positive or nil" unless sr.nil? || (sr.is_a?(Integer) && sr.positive?)
        raise Muze::ParameterError, "mono must be true, false, :mean, :left, :right, or :weighted" unless [true, false, :mean, :left, :right, :weighted].include?(mono)
        raise Muze::ParameterError, "offset must be >= 0" if offset.negative?
        raise Muze::ParameterError, "normalize must be true or false" unless [true, false].include?(normalize)
        raise Muze::ParameterError, "weights must be an Array when mono is :weighted" if mono == :weighted && !weights.is_a?(Array)
        raise Muze::ParameterError, "max_bytes must be positive" if max_bytes && (!max_bytes.is_a?(Integer) || max_bytes <= 0)
        dtype_class(dtype)
        return if duration.nil? || duration.positive?

        raise Muze::ParameterError, "duration must be positive"
      end
      private_class_method :validate_args!

      def validate_source_size!(source, max_bytes:)
        return unless max_bytes && source.fetch(:path?)

        size = File.size(source.fetch(:input))
        raise Muze::AudioLoadError, "Audio file is too large (#{size} bytes > #{max_bytes} bytes)" if size > max_bytes
      end
      private_class_method :validate_source_size!

      def select_backend(source)
        extension = source.fetch(:extension)
        backend = BACKENDS.find { |candidate| candidate.supported_extension?(extension) }

        raise Muze::UnsupportedFormatError, unsupported_format_message(extension) unless backend
        if !source.fetch(:path?) && backend != WavifyBackend
          raise Muze::UnsupportedFormatError, "IO/StringIO loading is currently supported for WAV input only"
        end
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

      def downmix(samples, mono:, weights:)
        return samples if mono == false
        return downmix_to_mono(samples) if mono == true || mono == :mean
        return downmix_weighted(samples, weights) if mono == :weighted
        return samples unless samples.first.is_a?(Array)

        channel_index = mono == :left ? 0 : samples.first.length - 1
        samples.map { |frame| frame.fetch(channel_index) }
      end
      private_class_method :downmix

      def downmix_weighted(samples, weights)
        return samples if samples.empty?
        return samples unless samples.first.is_a?(Array)
        raise Muze::ParameterError, "weights length must match channel count" unless weights.length == samples.first.length

        weight_sum = weights.sum(0.0)
        raise Muze::ParameterError, "weights must not sum to zero" if weight_sum.abs <= 1.0e-12

        samples.map do |frame|
          frame.each_with_index.sum { |sample, index| sample * weights[index] } / weight_sum
        end
      end
      private_class_method :downmix_weighted

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
