# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-03-04

### Added

- Core architecture for the `muze` gem with `RAF` alias.
- WAV loading with normalization, mono mixdown, offset/duration slicing.
- STFT/ISTFT pipeline and dB conversion helpers.
- Window functions (`hann`, `hamming`, `blackman`, `ones`).
- Mel filterbank, mel spectrogram, DCT-II, MFCC, delta features.
- Spectral features (centroid, bandwidth, rolloff, flatness, contrast, zcr, rms).
- Chroma features, onset detection, beat tracking, tempogram.
- Effects (`hpss`, `time_stretch`, `pitch_shift`, `trim`).
- SVG-based visualization (`specshow`, `waveshow`).
- Sinc-based resampler and optional C extension scaffold.
- CI workflow for Ruby 3.1/3.2/3.3 with RSpec.
