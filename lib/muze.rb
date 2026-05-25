# frozen_string_literal: true

require "numo/pocketfft"

require_relative "muze/version"
require_relative "muze/errors"
require_relative "muze/native"
require_relative "muze/core/audio"
require_relative "muze/core/windows"
require_relative "muze/core/matrix"
require_relative "muze/core/frames"
require_relative "muze/core/stft"
require_relative "muze/core/resample"
require_relative "muze/core/dct"
require_relative "muze/io/audio_loader"
require_relative "muze/io/audio_writer"
require_relative "muze/filters/mel"
require_relative "muze/filters/chroma_filter"
require_relative "muze/feature/mfcc"
require_relative "muze/feature/spectral"
require_relative "muze/feature/chroma"
require_relative "muze/feature/aggregation"
require_relative "muze/feature/context"
require_relative "muze/onset/onset_detect"
require_relative "muze/beat/beat_track"
require_relative "muze/effects/harmonic_percussive"
require_relative "muze/effects/time_stretch"
require_relative "muze/display/specshow"

# Main entrypoint for Muze API.
module Muze
  class << self
    # @param path [String]
    # @param sr [Integer, nil]
    # @param mono [Boolean, Symbol]
    # @param offset [Float]
    # @param duration [Float, nil]
    # @param dtype [Class, Symbol]
    # @param normalize [Boolean]
    # @return [Array(Numo::SFloat, Integer)]
    def load(path, sr: 22_050, mono: true, offset: 0.0, duration: nil, dtype: Numo::SFloat, normalize: false, format: nil, weights: nil, max_bytes: nil)
      Muze::IO::AudioLoader.load(path, sr:, mono:, offset:, duration:, dtype:, normalize:, format:, weights:, max_bytes:)
    end

    # @return [Hash]
    def info(path, format: nil)
      Muze::IO::AudioLoader.info(path, format:)
    end

    # @return [Object] the output path or IO object
    def write(path, y, sr:, normalize: false, format: :wav)
      Muze::IO::AudioWriter.write(path, y, sr:, normalize:, format:)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param n_fft [Integer]
    # @param hop_length [Integer]
    # @param win_length [Integer, nil]
    # @param window [Symbol]
    # @param center [Boolean]
    # @param pad_mode [Symbol]
    # @param pad_end [Boolean]
    # @return [Numo::DComplex]
    def stft(y, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: true, pad_mode: :reflect, pad_end: false)
      Muze::Core::STFT.stft(y, n_fft:, hop_length:, win_length:, window:, center:, pad_mode:, pad_end:)
    end

    # @param stft_matrix [Numo::DComplex]
    # @param hop_length [Integer]
    # @param win_length [Integer, nil]
    # @param window [Symbol]
    # @param center [Boolean]
    # @param length [Integer, nil]
    # @return [Numo::SFloat]
    def istft(stft_matrix, hop_length: 512, win_length: nil, window: :hann, center: true, length: nil, dtype: Numo::SFloat)
      Muze::Core::STFT.istft(stft_matrix, hop_length:, win_length:, window:, center:, length:, dtype:)
    end

    # @param stft_matrix [Numo::DComplex]
    # @return [Array(Numo::SFloat, Numo::DComplex)]
    def magphase(stft_matrix, eps: Muze::Core::STFT::EPSILON, dtype: Numo::SFloat)
      Muze::Core::STFT.magphase(stft_matrix, eps:, dtype:)
    end

    # @return [Array<Numo::DComplex>]
    def stft_stream(chunks, n_fft: 2048, hop_length: 512, win_length: nil, window: :hann, center: false, pad_mode: :reflect)
      Muze::Core::STFT.stft_stream(chunks, n_fft:, hop_length:, win_length:, window:, center:, pad_mode:)
    end

    # @param s [Numo::NArray]
    # @param ref [Float, Symbol, Proc]
    # @param amin [Float]
    # @param top_db [Float, nil]
    # @return [Numo::SFloat]
    def amplitude_to_db(s, ref: 1.0, amin: 1.0e-5, top_db: 80.0, abs: false)
      Muze::Core::STFT.amplitude_to_db(s, ref:, amin:, top_db:, abs:)
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

    # @return [Numo::SFloat]
    def fft_frequencies(sr:, n_fft:)
      Muze::Core::STFT.fft_frequencies(sr:, n_fft:)
    end

    # @return [Float, Numo::SFloat]
    def frames_to_time(frames, sr:, hop_length:)
      Muze::Core::STFT.frames_to_time(frames, sr:, hop_length:)
    end

    # @return [Integer, Numo::SFloat]
    def time_to_frames(times, sr:, hop_length:)
      Muze::Core::STFT.time_to_frames(times, sr:, hop_length:)
    end

    # @return [Integer, Numo::SFloat]
    def frames_to_samples(frames, hop_length:)
      Muze::Core::STFT.frames_to_samples(frames, hop_length:)
    end

    # @return [Integer, Numo::SFloat]
    def samples_to_frames(samples, hop_length:)
      Muze::Core::STFT.samples_to_frames(samples, hop_length:)
    end

    # @return [Float, Numo::SFloat]
    def samples_to_time(samples, sr:)
      Muze::Core::STFT.samples_to_time(samples, sr:)
    end

    # @return [Integer, Numo::SFloat]
    def time_to_samples(times, sr:)
      Muze::Core::STFT.time_to_samples(times, sr:)
    end

    # @return [Boolean]
    def valid_audio?(y, allow_empty: false)
      Muze::Core::Audio.valid_audio?(y, allow_empty:)
    end

    # @return [Numo::SFloat]
    def normalize(y, peak: 1.0, axis: nil)
      Muze::Core::Audio.normalize(y, peak:, axis:)
    end

    # @return [Numo::SFloat]
    def remix(y, intervals, units: :samples, sr: nil, hop_length: 512)
      Muze::Core::Audio.remix(y, intervals, units:, sr:, hop_length:)
    end

    # @param y [Numo::SFloat, Array<Float>]
    # @param orig_sr [Integer]
    # @param target_sr [Integer]
    # @param res_type [Symbol]
    # @param target_length [Integer, nil]
    # @return [Numo::SFloat]
    def resample(y, orig_sr:, target_sr:, res_type: :sinc, target_length: nil, taps: 16, beta: 8.6, cutoff: nil)
      Muze::Core::Resample.resample(y, orig_sr:, target_sr:, res_type:, target_length:, taps:, beta:, cutoff:)
    end

    # @param sr [Integer]
    # @param n_fft [Integer]
    # @param n_mels [Integer]
    # @param fmin [Float]
    # @param fmax [Float, nil]
    # @param htk [Boolean]
    # @return [Numo::SFloat]
    def mel(sr: 22_050, n_fft: 2048, n_mels: 128, fmin: 0.0, fmax: nil, htk: false, norm: nil)
      Muze::Filters.mel(sr:, n_fft:, n_mels:, fmin:, fmax:, htk:, norm:)
    end

    # @return [Numo::SFloat]
    def mel_frequencies(n_mels:, fmin:, fmax:, htk: false)
      Muze::Filters.mel_frequencies(n_mels:, fmin:, fmax:, htk:)
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
    def melspectrogram(y: nil, sr: 22_050, s: nil, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil, power: 2.0, center: true, window: :hann, pad_mode: :reflect, norm: nil, s_kind: :power)
      Muze::Feature.melspectrogram(y:, sr:, s:, n_fft:, hop_length:, n_mels:, fmin:, fmax:, power:, center:, window:, pad_mode:, norm:, s_kind:)
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
    def mfcc(y: nil, sr: 22_050, s: nil, n_mfcc: 20, n_fft: 2048, hop_length: 512, n_mels: 128, fmin: 0.0, fmax: nil, dct_type: 2, lifter: 0, norm: :ortho, s_kind: :mel_power)
      Muze::Feature.mfcc(y:, sr:, s:, n_mfcc:, n_fft:, hop_length:, n_mels:, fmin:, fmax:, dct_type:, lifter:, norm:, s_kind:)
    end

    # @param data [Numo::SFloat]
    # @param order [Integer]
    # @param width [Integer]
    # @param mode [Symbol]
    # @return [Numo::SFloat]
    def delta(data, order: 1, width: 9, mode: :interp)
      Muze::Feature.delta(data, order:, width:, mode:)
    end

    # @return [Muze::Feature::Context]
    def feature_context(y:, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      Muze::Feature.context(y:, sr:, n_fft:, hop_length:, center:, pad_mode:)
    end

    # @return [Hash]
    def features(y:, sr: 22_050, features: Muze::Feature::Context::DEFAULT_FEATURES, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect)
      Muze::Feature.extract(y:, sr:, features:, n_fft:, hop_length:, center:, pad_mode:)
    end

    # @return [Numo::SFloat]
    def beat_sync(data, beats:, aggregate: :mean)
      Muze::Feature.beat_sync(data, beats:, aggregate:)
    end

    # @return [Numo::SFloat]
    def spectral_centroid(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_centroid(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_bandwidth(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, p: 2, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_bandwidth(y:, s:, sr:, n_fft:, hop_length:, p:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_rolloff(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, roll_percent: 0.85, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_rolloff(y:, s:, sr:, n_fft:, hop_length:, roll_percent:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_flatness(y: nil, s: nil, n_fft: 2048, hop_length: 512, amin: 1.0e-10, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_flatness(y:, s:, n_fft:, hop_length:, amin:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_contrast(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, n_bands: 6, quantile: 0.02, fmin: 200.0, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_contrast(y:, s:, sr:, n_fft:, hop_length:, n_bands:, quantile:, fmin:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_flux(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_flux(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_entropy(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_entropy(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_crest(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_crest(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_slope(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_slope(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def spectral_decrease(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.spectral_decrease(y:, s:, sr:, n_fft:, hop_length:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def poly_features(y: nil, s: nil, sr: 22_050, n_fft: 2048, hop_length: 512, order: 1, frequency: nil, center: true, pad_mode: :reflect, s_kind: :magnitude)
      Muze::Feature.poly_features(y:, s:, sr:, n_fft:, hop_length:, order:, frequency:, center:, pad_mode:, s_kind:)
    end

    # @return [Numo::SFloat]
    def zero_crossing_rate(y, frame_length: 2048, hop_length: 512, threshold: 0.0, center: false)
      Muze::Feature.zero_crossing_rate(y, frame_length:, hop_length:, threshold:, center:)
    end

    # @return [Numo::SFloat]
    def rms(y: nil, s: nil, frame_length: 2048, hop_length: 512, center: false)
      Muze::Feature.rms(y:, s:, frame_length:, hop_length:, center:)
    end

    # @return [Numo::SFloat]
    def tempogram(y: nil, onset_envelope: nil, sr: 22_050, hop_length: 512, win_length: 384, normalize: false)
      Muze::Feature.tempogram(y:, onset_envelope:, sr:, hop_length:, win_length:, normalize:)
    end

    # @return [Numo::SFloat]
    def chroma(sr:, n_fft:, n_chroma: 12, tuning: 0.0, ctroct: nil, octwidth: nil)
      Muze::Filters.chroma(sr:, n_fft:, n_chroma:, tuning:, ctroct:, octwidth:)
    end

    # @return [Numo::SFloat]
    def chroma_stft(y: nil, sr: 22_050, s: nil, n_chroma: 12, n_fft: 2048, hop_length: 512, norm: 2, tuning: 0.0, ctroct: nil, octwidth: nil)
      Muze::Feature.chroma_stft(y:, sr:, s:, n_chroma:, n_fft:, hop_length:, norm:, tuning:, ctroct:, octwidth:)
    end

    # @return [Numo::SFloat]
    def tonnetz(y: nil, chroma: nil, sr: 22_050, n_fft: 2048, hop_length: 512)
      Muze::Feature.tonnetz(y:, chroma:, sr:, n_fft:, hop_length:)
    end

    # @return [Numo::SFloat]
    def onset_strength(y: nil, sr: 22_050, s: nil, hop_length: 512, n_fft: 2048, lag: 1, log: false, max_size: 1, normalize: false)
      Muze::Onset.onset_strength(y:, sr:, s:, hop_length:, n_fft:, lag:, log:, max_size:, normalize:)
    end

    # @return [Array<Integer, Float>]
    def onset_detect(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, backtrack: false, units: :frames, pre_max: 1, post_max: 1, pre_avg: 1, post_avg: 1, delta: nil, wait: 0, adaptive: false, energy: nil)
      Muze::Onset.onset_detect(y:, sr:, onset_envelope:, hop_length:, backtrack:, units:, pre_max:, post_max:, pre_avg:, post_avg:, delta:, wait:, adaptive:, energy:)
    end

    # @return [Array(Float, Array<Integer>)]
    def beat_track(y: nil, sr: 22_050, onset_envelope: nil, hop_length: 512, start_bpm: 120.0, tightness: 100, min_bpm: 30.0, max_bpm: 240.0, bpm: nil, fill_missing: true, return_metadata: false)
      Muze::Beat.beat_track(y:, sr:, onset_envelope:, hop_length:, start_bpm:, tightness:, min_bpm:, max_bpm:, bpm:, fill_missing:, return_metadata:)
    end

    # @return [Numo::SFloat]
    def tempo_frequencies(sr: 22_050, hop_length: 512, win_length: 384)
      Muze::Beat.tempo_frequencies(sr:, hop_length:, win_length:)
    end

    # @return [Array(Numo::SFloat, Numo::SFloat)]
    def hpss(y, kernel_size: 31, power: 2.0, margin: 1.0, n_fft: 2048, hop_length: 512, return_masks: false)
      Muze::Effects.hpss(y, kernel_size:, power:, margin:, n_fft:, hop_length:, return_masks:)
    end

    # @return [Numo::SFloat]
    def time_stretch(y, rate: 1.0, n_fft: nil, hop_length: nil, method: :phase_vocoder, phase_lock: false, force_phase_vocoder: false)
      Muze::Effects.time_stretch(y, rate:, n_fft:, hop_length:, method:, phase_lock:, force_phase_vocoder:)
    end

    # @return [Numo::SFloat]
    def pitch_shift(y, sr: 22_050, n_steps: 0, bins_per_octave: 12, res_type: :auto, normalize: false, clip: nil)
      Muze::Effects.pitch_shift(y, sr:, n_steps:, bins_per_octave:, res_type:, normalize:, clip:)
    end

    # @return [Array(Numo::SFloat, Array<Integer>)]
    def trim(y, top_db: 60, frame_length: 2048, hop_length: 512, ref: :max, aggregate: :mean)
      Muze::Effects.trim(y, top_db:, frame_length:, hop_length:, ref:, aggregate:)
    end

    # @return [Numo::SFloat]
    def preemphasis(y, coef: 0.97)
      Muze::Effects.preemphasis(y, coef:)
    end

    # @return [Numo::SFloat]
    def deemphasis(y, coef: 0.97)
      Muze::Effects.deemphasis(y, coef:)
    end

    # @return [String]
    def specshow(data, sr: 22_050, hop_length: 512, x_axis: :time, y_axis: :linear, output: nil, width: 800, height: 400, cmap: :heat, vmin: nil, vmax: nil, fragment: false)
      Muze::Display.specshow(data, sr:, hop_length:, x_axis:, y_axis:, output:, width:, height:, cmap:, vmin:, vmax:, fragment:)
    end

    # @return [String]
    def waveshow(y, sr: 22_050, output: nil, width: 800, height: 240, normalize: true, channels: :overlay)
      Muze::Display.waveshow(y, sr:, output:, width:, height:, normalize:, channels:)
    end

    # @return [String]
    def onsetshow(onset_envelope, sr: 22_050, hop_length: 512, output: nil, width: 800, height: 160, normalize: true)
      Muze::Display.onsetshow(onset_envelope, sr:, hop_length:, output:, width:, height:, normalize:)
    end
  end
end

RAF = Muze if ENV.fetch("MUZE_DEFINE_RAF", "1") != "0" && !Object.const_defined?(:RAF)
