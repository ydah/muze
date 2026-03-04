# frozen_string_literal: true

require "numo/narray"

require_relative "muze/version"
require_relative "muze/errors"
require_relative "muze/core/windows"
require_relative "muze/core/stft"
require_relative "muze/core/resample"
require_relative "muze/core/dct"
require_relative "muze/io/audio_loader"
require_relative "muze/filters/mel"
require_relative "muze/filters/chroma_filter"
require_relative "muze/feature/mfcc"
require_relative "muze/feature/spectral"
require_relative "muze/feature/chroma"
require_relative "muze/onset/onset_detect"
require_relative "muze/beat/beat_track"
require_relative "muze/effects/harmonic_percussive"
require_relative "muze/effects/time_stretch"
require_relative "muze/display/specshow"

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

    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @param htk [Boolean]
    # @return [Numo::SFloat]
    def mel(sr: 22_050, n_fft: 2048, n_mels: 128, fmin: 0.0, fmax: nil, htk: false)
      Muze::Filters.mel(sr:, n_fft:, n_mels:, fmin:, fmax:, htk:)
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @return [Numo::SFloat]
    def melspectrogram(y: nil, sr: 22_050, s: nil, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil)
      Muze::Feature.melspectrogram(y:, sr:, s:, n_fft:, hop_length:, n_mels:, fmin:, fmax:)
    end

    # @param y [Numo::SFloat, Array<Float>, nil]
    # @param sr [Integer]
    # @param s [Numo::SFloat, nil]
    # @param n_mfcc [Integer]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @return [Numo::SFloat]
    def mfcc(y: nil, sr: 22_050, s: nil, n_mfcc: 20, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil)
      Muze::Feature.mfcc(y:, sr:, s:, n_mfcc:, n_fft:, hop_length:, n_mels:, fmin:, fmax:)
    end

    # @param data [Numo::SFloat]
    # @param order [Integer]
    # @param width [Integer]
    # @param mode [Symbol]
    # @return [Numo::SFloat]
    def delta(data, order: 1, width: 9, mode: :interp)
      Muze::Feature.delta(data, order:, width:, mode:)
    end

    # @return [Numo::SFloat]
    def spectral_centroid(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512)
      Muze::Feature.spectral_centroid(y:, s:, sr:, n_fft:, hop_length:)
    end

    # @return [Numo::SFloat]
    def spectral_bandwidth(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, p: 2)
      Muze::Feature.spectral_bandwidth(y:, s:, sr:, n_fft:, hop_length:, p:)
    end

    # @return [Numo::SFloat]
    def spectral_rolloff(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, roll_percent: 0.85)
      Muze::Feature.spectral_rolloff(y:, s:, sr:, n_fft:, hop_length:, roll_percent:)
    end

    # @return [Numo::SFloat]
    def spectral_flatness(y: nil, s: nil, n_fft: 2048, hop_length: 512, amin: 1.0e-10)
      Muze::Feature.spectral_flatness(y:, s:, n_fft:, hop_length:, amin:)
    end

    # @return [Numo::SFloat]
    def spectral_contrast(y: nil, s: nil, n_fft: 2048, hop_length: 512, n_bands: 6, quantile: 0.02)
      Muze::Feature.spectral_contrast(y:, s:, n_fft:, hop_length:, n_bands:, quantile:)
    end

    # @return [Numo::SFloat]
    def zero_crossing_rate(y, frame_length: 2048, hop_length: 512)
      Muze::Feature.zero_crossing_rate(y, frame_length:, hop_length:)
    end

    # @return [Numo::SFloat]
    def rms(y: nil, s: nil, frame_length: 2048, hop_length: 512)
      Muze::Feature.rms(y:, s:, frame_length:, hop_length:)
    end

    # @return [Numo::SFloat]
    def tempogram(y: nil, onset_envelope: nil, sr: 22_050, hop_length: 512, win_length: 384)
      Muze::Feature.tempogram(y:, onset_envelope:, sr:, hop_length:, win_length:)
    end

    # @return [Numo::SFloat]
    def chroma(sr:, n_fft:, n_chroma: 12, tuning: 0.0)
      Muze::Filters.chroma(sr:, n_fft:, n_chroma:, tuning:)
    end

    # @return [Numo::SFloat]
    def chroma_stft(y: nil, sr: 22_050, s: nil, n_chroma: 12, n_fft: 2048, hop_length: 512, norm: 2)
      Muze::Feature.chroma_stft(y:, sr:, s:, n_chroma:, n_fft:, hop_length:, norm:)
    end

    # @return [Numo::SFloat]
    def onset_strength(y: nil, sr: 22_050, s: nil, hop_length: 512, n_fft: 2048)
      Muze::Onset.onset_strength(y:, sr:, s:, hop_length:, n_fft:)
    end

    # @return [Array<Integer, Float>]
    def onset_detect(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, backtrack: false, units: :frames)
      Muze::Onset.onset_detect(y:, sr:, onset_envelope:, hop_length:, backtrack:, units:)
    end

    # @return [Array(Float, Array<Integer>)]
    def beat_track(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, start_bpm: 120.0, tightness: 100)
      Muze::Beat.beat_track(y:, sr:, onset_envelope:, hop_length:, start_bpm:, tightness:)
    end

    # @return [Array(Numo::SFloat, Numo::SFloat)]
    def hpss(y, kernel_size: 31, power: 2.0, margin: 1.0, n_fft: 2048, hop_length: 512)
      Muze::Effects.hpss(y, kernel_size:, power:, margin:, n_fft:, hop_length:)
    end

    # @return [Numo::SFloat]
    def time_stretch(y, rate: 1.0)
      Muze::Effects.time_stretch(y, rate:)
    end

    # @return [Numo::SFloat]
    def pitch_shift(y, sr: 22_050, n_steps: 0)
      Muze::Effects.pitch_shift(y, sr:, n_steps:)
    end

    # @return [Array(Numo::SFloat, Array<Integer>)]
    def trim(y, top_db: 60, frame_length: 2048, hop_length: 512)
      Muze::Effects.trim(y, top_db:, frame_length:, hop_length:)
    end

    # @return [String]
    def specshow(data, sr: 22_050, hop_length: 512, x_axis: :time, y_axis: :linear, output: nil)
      Muze::Display.specshow(data, sr:, hop_length:, x_axis:, y_axis:, output:)
    end

    # @return [String]
    def waveshow(y, sr: 22_050, output: nil)
      Muze::Display.waveshow(y, sr:, output:)
    end
  end
end

RAF = Muze unless Object.const_defined?(:RAF)
