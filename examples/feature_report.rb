#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/feature_report.rb path/to/audio.wav

require_relative "../lib/muze"

input_path = ARGV[0]
abort("Usage: bundle exec ruby examples/feature_report.rb path/to/audio.wav") unless input_path

target_sr = 22_050
n_fft = 1024
hop_length = 256
n_mfcc = 13
n_mels = 40

y, sr = Muze.load(input_path, sr: target_sr, mono: true)
mfcc = Muze.mfcc(y:, sr:, n_mfcc:, n_fft:, hop_length:, n_mels:)
delta = Muze.delta(mfcc, order: 1, width: 9)
centroid = Muze.spectral_centroid(y:, sr:, n_fft:, hop_length:)
bandwidth = Muze.spectral_bandwidth(y:, sr:, n_fft:, hop_length:)
rolloff = Muze.spectral_rolloff(y:, sr:, n_fft:, hop_length:)
flatness = Muze.spectral_flatness(y:, n_fft:, hop_length:)
zcr = Muze.zero_crossing_rate(y, frame_length: n_fft, hop_length:)
rms = Muze.rms(y:, frame_length: n_fft, hop_length:)

puts "Input: #{input_path}"
puts "Sample rate: #{sr} Hz"
puts format("Duration: %.2f s", y.size.to_f / sr)
puts "MFCC shape: #{mfcc.shape.join(' x ')}"
puts "Delta shape: #{delta.shape.join(' x ')}"
puts format("Mean spectral centroid: %.2f Hz", centroid.mean.to_f)
puts format("Mean spectral bandwidth: %.2f Hz", bandwidth.mean.to_f)
puts format("Mean spectral rolloff: %.2f Hz", rolloff.mean.to_f)
puts format("Mean spectral flatness: %.4f", flatness.mean.to_f)
puts format("Mean zero-crossing rate: %.4f", zcr.mean.to_f)
puts format("Mean RMS: %.4f", rms.mean.to_f)
