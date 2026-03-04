# frozen_string_literal: true

require "numo/narray"

require_relative "muze/version"
require_relative "muze/errors"
require_relative "muze/core/windows"
require_relative "muze/core/stft"
require_relative "muze/core/resample"
require_relative "muze/io/audio_loader"

# Main entrypoint for Muze API.
module Muze
  class << self
    # @param path [String]
    # @param sr [Integer]
    # @param mono [Boolean]
    # @param offset [Float]
    # @param duration [Float, nil]
    # @return [Array(Numo::SFloat, Integer)]
    def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil)
      Muze::IO::AudioLoader.load(path, sr:, mono:, offset:, duration:)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param win_length [Integer, nil]
    # @param window [Symbol]
    # @param center [Boolean]
    # @param pad_mode [Symbol]
    # @return [Numo::DComplex]
    def stft(y, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: true, pad_mode: :reflect)
      Muze::Core::STFT.stft(y, n_fft:, hop_length:, win_length:, window:, center:, pad_mode:)
    end

    # @param stft_matrix [Numo::DComplex]
    # @param hop_length [Integer]
    # @param win_length [Integer, nil]
    # @param window [Symbol]
    # @param center [Boolean]
    # @param length [Integer, nil]
    # @return [Numo::SFloat]
    def istft(stft_matrix, hop_length: 512, win_length: nil, window: :hann, center: true, length: nil)
      Muze::Core::STFT.istft(stft_matrix, hop_length:, win_length:, window:, center:, length:)
    end

    # @param stft_matrix [Numo::DComplex]
    # @return [Array(Numo::SFloat, Numo::DComplex)]
    def magphase(stft_matrix)
      Muze::Core::STFT.magphase(stft_matrix)
    end

    # @param s [Numo::NArray]
    # @param ref [Float, Symbol, Proc]
    # @param amin [Float]
    # @param top_db [Float, nil]
    # @return [Numo::SFloat]
    def amplitude_to_db(s, ref: 1.0, amin: 1.0e-5, top_db: 80.0)
      Muze::Core::STFT.amplitude_to_db(s, ref:, amin:, top_db:)
    end

    # @param s [Numo::NArray]
    # @param ref [Float, Symbol, Proc]
    # @param amin [Float]
    # @param top_db [Float, nil]
    # @return [Numo::SFloat]
    def power_to_db(s, ref: 1.0, amin: 1.0e-10, top_db: 80.0)
      Muze::Core::STFT.power_to_db(s, ref:, amin:, top_db:)
    end

    # @param s_db [Numo::NArray]
    # @param ref [Float]
    # @return [Numo::SFloat]
    def db_to_amplitude(s_db, ref: 1.0)
      Muze::Core::STFT.db_to_amplitude(s_db, ref:)
    end

    # @param s_db [Numo::NArray]
    # @param ref [Float]
    # @return [Numo::SFloat]
    def db_to_power(s_db, ref: 1.0)
      Muze::Core::STFT.db_to_power(s_db, ref:)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param orig_sr [Integer]
    # @param target_sr [Integer]
    # @param res_type [Symbol]
    # @return [Numo::SFloat]
    def resample(y, orig_sr:, target_sr:, res_type: :linear)
      Muze::Core::Resample.resample(y, orig_sr:, target_sr:, res_type:)
    end
  end
end

RAF = Muze unless Object.const_defined?(:RAF)
