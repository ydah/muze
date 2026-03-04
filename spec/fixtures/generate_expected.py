"""
Generate expected fixture values with librosa.
Usage: python spec/fixtures/generate_expected.py
"""

import json
from pathlib import Path

import librosa
import numpy as np

FIXTURE_DIR = Path(__file__).resolve().parent


def save_json(data, filename):
    def convert(obj):
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, (np.floating, float)):
            return float(obj)
        if isinstance(obj, (np.integer, int)):
            return int(obj)
        return obj

    payload = {key: convert(value) for key, value in data.items()}
    path = FIXTURE_DIR / filename
    with path.open("w", encoding="utf-8") as f:
        json.dump(payload, f)


def generate_stft_expected():
    sr = 22050
    t = np.linspace(0.0, 1.0, sr, endpoint=False)
    y = np.sin(2 * np.pi * 440 * t).astype(np.float32)

    d = librosa.stft(y, n_fft=2048, hop_length=512)
    s = np.abs(d)
    s_db = librosa.power_to_db(s**2)

    save_json(
        {
            "sr": sr,
            "y": y,
            "stft_real": d.real,
            "stft_imag": d.imag,
            "magnitude": s,
            "power_db": s_db,
        },
        "stft_expected.json",
    )


def generate_feature_expected():
    sr = 22050
    t = np.linspace(0.0, 1.0, sr, endpoint=False)
    y = np.sin(2 * np.pi * 440 * t).astype(np.float32)

    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    mel = librosa.feature.melspectrogram(y=y, sr=sr)
    centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
    bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
    zcr = librosa.feature.zero_crossing_rate(y)
    rms = librosa.feature.rms(y=y)

    save_json(
        {
            "mfcc": mfcc,
            "mel": mel,
            "spectral_centroid": centroid,
            "spectral_bandwidth": bandwidth,
            "zcr": zcr,
            "rms": rms,
        },
        "feature_expected.json",
    )


if __name__ == "__main__":
    generate_stft_expected()
    generate_feature_expected()
    print(f"Generated fixtures in {FIXTURE_DIR}")
