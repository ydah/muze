# Muze

Muze is a Ruby audio feature extraction library inspired by `librosa`.
It provides a full pipeline from audio loading to spectral analysis, feature extraction,
rhythm analysis, effects, and lightweight visualization.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "muze"
```

Then execute:

```bash
bundle install
```

Or install directly:

```bash
gem install muze
```

## Quick Start

```ruby
require "muze"

y, sr = RAF.load("sample.wav", sr: 22_050)
mel = RAF.melspectrogram(y:, sr:)
mfcc = RAF.mfcc(y:, sr:, n_mfcc: 13)
tempo, beats = RAF.beat_track(y:, sr:)
RAF.specshow(Muze.power_to_db(mel), output: "mel.svg")
```

## Main Features

- Audio I/O: `RAF.load` (`wav`, `flac`, `mp3`, `ogg`)
- STFT stack: `RAF.stft`, `RAF.istft`, `RAF.magphase`
- Scale helpers: `RAF.power_to_db`, `RAF.amplitude_to_db`
- Filters: `RAF.mel`, `RAF.chroma`
- Features: `RAF.melspectrogram`, `RAF.mfcc`, `RAF.delta`
- Spectral descriptors: centroid, bandwidth, rolloff, flatness, contrast, zcr, rms
- Rhythm: `RAF.onset_strength`, `RAF.onset_detect`, `RAF.beat_track`, `RAF.tempogram`
- Effects: `RAF.hpss`, `RAF.time_stretch`, `RAF.pitch_shift`, `RAF.trim`
- Visualization: `RAF.specshow`, `RAF.waveshow`

`wav` is loaded with `wavify`, and `flac/mp3/ogg` requires `ffmpeg` + `ffprobe`
available on `PATH`.

## Development

```bash
bundle install
bundle exec rspec
```

Benchmark and regression check:

```bash
bundle exec rake bench
```

This writes a JSON report to `benchmarks/reports/latest.json` and compares metrics
against `benchmarks/baseline.json`. To refresh the baseline:

```bash
MUZE_BENCH_UPDATE_BASELINE=1 bundle exec rake bench
```

Quality regression thresholds for effects are documented in
`benchmarks/quality_thresholds.md`.

Optional native extension:

```bash
bundle exec rake compile
```

Generate API docs:

```bash
bundle exec yard doc
```

## License

MIT
