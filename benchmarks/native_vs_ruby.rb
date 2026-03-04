# frozen_string_literal: true

require "benchmark"
require_relative "../lib/muze"

signal = Array.new(200_000) { rand(-1.0..1.0) }
values = Array.new(255) { rand }

puts "Native extension loaded: #{Muze::Native.extension_loaded?}"

Benchmark.bm(24) do |x|
  x.report("frame_slices") do
    20.times { Muze::Native.frame_slices(signal, 2048, 512) }
  end

  x.report("median1d") do
    2000.times { Muze::Native.median1d(values) }
  end

  x.report("sinc_resample") do
    10.times { Muze.resample(signal, orig_sr: 44_100, target_sr: 22_050, res_type: :sinc) }
  end
end
