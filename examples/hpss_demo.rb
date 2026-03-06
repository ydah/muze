#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: bundle exec ruby examples/hpss_demo.rb path/to/audio.wav [output_prefix]

require "fileutils"
require_relative "../lib/muze"

def render_mel(signal, sr:, hop_length:, output_path:)
  mel = Muze.melspectrogram(y: signal, sr:, n_fft: 2048, hop_length:, n_mels: 128)
  Muze.specshow(Muze.power_to_db(mel), sr:, hop_length:, y_axis: :mel, output: output_path)
end

input_path = ARGV[0]
abort("Usage: bundle exec ruby examples/hpss_demo.rb path/to/audio.wav [output_prefix]") unless input_path

sample_name = File.basename(input_path, ".*")
output_prefix = ARGV[1] || File.expand_path("output/#{sample_name}", __dir__)
FileUtils.mkdir_p(File.dirname(output_prefix))

target_sr = 22_050
hop_length = 512

y, sr = Muze.load(input_path, sr: target_sr, mono: true)
harmonic, percussive = Muze.hpss(y, kernel_size: 31, n_fft: 2048, hop_length:)

harmonic_wave_path = "#{output_prefix}_harmonic_wave.svg"
percussive_wave_path = "#{output_prefix}_percussive_wave.svg"
harmonic_mel_path = "#{output_prefix}_harmonic_mel.svg"
percussive_mel_path = "#{output_prefix}_percussive_mel.svg"

Muze.waveshow(harmonic, sr:, output: harmonic_wave_path)
Muze.waveshow(percussive, sr:, output: percussive_wave_path)
render_mel(harmonic, sr:, hop_length:, output_path: harmonic_mel_path)
render_mel(percussive, sr:, hop_length:, output_path: percussive_mel_path)

harmonic_rms = Muze.rms(y: harmonic, frame_length: 2048, hop_length:).mean.to_f
percussive_rms = Muze.rms(y: percussive, frame_length: 2048, hop_length:).mean.to_f

puts "Input: #{input_path}"
puts format("Harmonic RMS: %.4f", harmonic_rms)
puts format("Percussive RMS: %.4f", percussive_rms)
puts "Wrote: #{harmonic_wave_path}"
puts "Wrote: #{percussive_wave_path}"
puts "Wrote: #{harmonic_mel_path}"
puts "Wrote: #{percussive_mel_path}"
