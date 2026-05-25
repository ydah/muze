# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-05-25

### Added

- Added broader audio I/O: WAV writing, source-rate preserving loads, `Pathname` and WAV `IO` inputs, stereo output, configurable downmixing, file metadata via `Muze.info`, and chunked reads via `Muze.load_stream`.
- Added streamed and long-file-friendly DSP APIs including `Muze.stft_stream`, `Muze.time_stretch_stream`, `Muze.pitch_shift_stream`, and `Muze.hpss_stream`.
- Added more STFT and conversion controls: explicit pad modes, trailing frame padding, periodic windows, custom windows, non-power-of-two even FFT lengths, frame/time/sample helpers, FFT frequencies, and configurable dB conversion.
- Added richer feature extraction: Slaney mel filters, mel frequencies, chroma tuning and octave weighting, MFCC liftering and input modes, delta edge modes, additional spectral descriptors, polynomial spectral features, tonnetz, beat-synchronous aggregation, and shared feature extraction via `Muze.feature_context` / `Muze.feature_stack`.
- Added rhythm controls for onset strength, onset detection, tempo estimation, normalized tempograms, fixed-BPM beat tracking, tempo frequency helpers, and beat metadata output.
- Added effects improvements: multi-channel processing, HPSS masks and margins, WSOLA/OLA time stretching, phase locking, pitch-shift controls, frame-energy trimming with interval units, and preemphasis/deemphasis.
- Added lightweight visualization upgrades: `specshow` axes, dimensions, color maps, value bounds, fragment output, image rendering, waveform envelope rendering, stereo waveform layouts, and onset envelope rendering.

### Changed

- The optional native extension is now built during gem installation when supported, while retaining the pure Ruby fallback.
- Audio loading now applies FFmpeg seek/duration controls before decoding and uses safer FFmpeg process handling.

## [0.1.0] - 2026-03-07

- Initial release.
