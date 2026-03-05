# Effects Quality Regression Thresholds

This document defines thresholds for `time_stretch` and `pitch_shift` regression tests.

## Signals

- Harmonic: 440Hz + 660Hz mixed sine wave (`2.0s`, `22_050Hz`)
- Transient: click impulses at fixed timestamps (`2.0s`, `22_050Hz`)

## Thresholds

- `time_stretch` dominant frequency drift:
  - Condition: `rate=2.0` and `rate=0.5`
  - Threshold: within `20Hz` from original dominant frequency
  - Rationale: keeps clear musical pitch identity while allowing FFT-bin granularity error.

- `time_stretch` transient alignment:
  - Condition: `rate=2.0`
  - Threshold: each detected click within `256 samples` from expected scaled position
  - Rationale: catches obvious transient collapse while tolerating local phase vocoder artifacts.

- `pitch_shift` octave peak movement:
  - Condition: `n_steps=+12`
  - Threshold: contains peaks near `880Hz` (`±25Hz`) and `1320Hz` (`±35Hz`)
  - Rationale: verifies octave translation for fundamental + harmonic pair.

These thresholds are intentionally conservative to avoid flaky CI failures while still
catching meaningful quality regressions.
