#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/load_and_specshow.rb path/to/audio.wav [output.svg]

require "fileutils"
require_relative "../lib/muze"

input_path = ARGV[0]
abort("Usage: bundle exec ruby examples/load_and_specshow.rb path/to/audio.wav [output.svg]") unless input_path

sample_name = File.basename(input_path, ".*")
output_path = ARGV[1] || File.expand_path("output/#{sample_name}_mel_spectrogram.svg", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

target_sr = 22_050
hop_length = 512
n_fft = 2048
n_mels = 128

y, sr = Muze.load(input_path, sr: target_sr, mono: true)
mel = Muze.melspectrogram(y:, sr:, n_fft:, hop_length:, n_mels:)
mel_db = Muze.power_to_db(mel)
Muze.specshow(mel_db, sr:, hop_length:, y_axis: :mel, output: output_path)

puts "Input: #{input_path}"
puts "Sample rate: #{sr} Hz"
puts format("Duration: %.2f s", y.size.to_f / sr)
puts "Mel shape: #{mel.shape.join(' x ')}"
puts "Wrote: #{output_path}"
