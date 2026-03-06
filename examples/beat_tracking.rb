#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/beat_tracking.rb path/to/audio.wav

require_relative "../lib/muze"

input_path = ARGV[0]
abort("Usage: bundle exec ruby examples/beat_tracking.rb path/to/audio.wav") unless input_path

target_sr = 22_050
n_fft = 1024
hop_length = 256

y, sr = Muze.load(input_path, sr: target_sr, mono: true)
onset_envelope = Muze.onset_strength(y:, sr:, hop_length:, n_fft:)
onset_times = Muze.onset_detect(onset_envelope:, sr:, hop_length:, backtrack: true, units: :time)
tempo, beat_frames = Muze.beat_track(onset_envelope:, sr:, hop_length:)
beat_times = beat_frames.map { |frame| (frame * hop_length.to_f) / sr }

puts "Input: #{input_path}"
puts format("Estimated tempo: %.2f BPM", tempo)
puts "Detected onsets: #{onset_times.length}"
puts "Detected beats: #{beat_times.length}"
puts "First onsets (s): #{onset_times.first(8).map { |time| format('%.3f', time) }.join(', ')}"
puts "First beats (s): #{beat_times.first(8).map { |time| format('%.3f', time) }.join(', ')}"
