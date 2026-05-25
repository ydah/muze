# frozen_string_literal: true

module Muze
  module Feature
    # Lightweight cache for feature extractors that share the same STFT.
    class Context
      DEFAULT_FEATURES = %i[
        melspectrogram
        chroma_stft
        spectral_centroid
        spectral_bandwidth
        spectral_rolloff
        spectral_flatness
        rms
        zero_crossing_rate
      ].freeze

      attr_reader :y, :sr, :n_fft, :hop_length, :center, :pad_mode

      def initialize(y:, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
        @y = y
        @sr = sr
        @n_fft = n_fft
        @hop_length = hop_length
        @center = center
        @pad_mode = pad_mode
        @cache = {}
      end

      def stft
        @cache[:stft] ||= Muze.stft(y, n_fft:, hop_length:, center:, pad_mode:)
      end

      def magnitude
        @cache[:magnitude] ||= Muze.magphase(stft).first
      end

      def power
        @cache[:power] ||= (magnitude**2).cast_to(Numo::SFloat)
      end

      def extract(features: DEFAULT_FEATURES)
        features.each_with_object({}) do |feature, results|
          results[feature] = fetch(feature)
        end
      end

      def fetch(feature)
        @cache[feature] ||= case feature
                            when :melspectrogram then Muze::Feature.melspectrogram(sr:, s: power, n_fft:, hop_length:)
                            when :chroma_stft then Muze::Feature.chroma_stft(sr:, s: magnitude, n_fft:, hop_length:)
                            when :spectral_centroid then Muze::Feature.spectral_centroid(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_bandwidth then Muze::Feature.spectral_bandwidth(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_rolloff then Muze::Feature.spectral_rolloff(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_flatness then Muze::Feature.spectral_flatness(s: magnitude, n_fft:, hop_length:)
                            when :spectral_flux then Muze::Feature.spectral_flux(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_entropy then Muze::Feature.spectral_entropy(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_crest then Muze::Feature.spectral_crest(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_slope then Muze::Feature.spectral_slope(s: magnitude, sr:, n_fft:, hop_length:)
                            when :spectral_decrease then Muze::Feature.spectral_decrease(s: magnitude, sr:, n_fft:, hop_length:)
                            when :poly_features then Muze::Feature.poly_features(s: magnitude, sr:, n_fft:, hop_length:)
                            when :tonnetz then Muze::Feature.tonnetz(chroma: fetch(:chroma_stft), sr:, n_fft:, hop_length:)
                            when :rms then Muze::Feature.rms(s: magnitude)
                            when :zero_crossing_rate then Muze::Feature.zero_crossing_rate(y, frame_length: n_fft, hop_length:)
                            else
                              raise Muze::ParameterError, "Unsupported feature: #{feature}"
                            end
      end
    end

    module_function

    def context(y:, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      Context.new(y:, sr:, n_fft:, hop_length:, center:, pad_mode:)
    end

    def extract(y:, sr: 22_050, features: Context::DEFAULT_FEATURES, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      context(y:, sr:, n_fft:, hop_length:, center:, pad_mode:).extract(features:)
    end
  end
end
