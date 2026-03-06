#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/chroma_svg.rb path/to/audio.wav [output.svg]

require "fileutils"
require_relative "../lib/muze"

note_names = %w[C C# D D# E F F# G G# A A# B].freeze
input_path = ARGV[0]
abort("Usage: bundle exec ruby examples/chroma_svg.rb path/to/audio.wav [output.svg]") unless input_path

sample_name = File.basename(input_path, ".*")
output_path = ARGV[1] || File.expand_path("output/#{sample_name}_chroma.svg", __dir__)
FileUtils.mkdir_p(File.dirname(output_path))

target_sr = 22_050
n_fft = 2048
hop_length = 512

y, sr = Muze.load(input_path, sr: target_sr, mono: true)
chroma = Muze.chroma_stft(y:, sr:, n_chroma: 12, n_fft:, hop_length:)
Muze.specshow(chroma, sr:, hop_length:, y_axis: :linear, output: output_path)

pitch_strengths = chroma.to_a.map do |row|
  row.sum(0.0) / [row.length, 1].max
end
dominant_pitch = note_names.fetch(pitch_strengths.each_with_index.max_by(&:first).last)

puts "Input: #{input_path}"
puts "Chroma shape: #{chroma.shape.join(' x ')}"
puts "Dominant pitch class: #{dominant_pitch}"
puts "Wrote: #{output_path}"
