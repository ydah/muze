# frozen_string_literal: true

require "tmpdir"
require "pathname"

RSpec.describe Muze::Display do
  describe ".specshow" do
    it "returns SVG content" do
      data = Numo::SFloat.new(8, 8).rand
      svg = described_class.specshow(data)

      expect(svg).to include("<svg")
      expect(svg).to include("</svg>")
    end

    it "writes output file" do
      data = Numo::SFloat.new(8, 8).rand
      Dir.mktmpdir do |dir|
        path = Pathname(File.join(dir, "spectrogram.svg"))
        described_class.specshow(data, output: path)

        expect(File.exist?(path)).to be(true)
      end
    end

    it "records axis metadata and supports alternate cmap" do
      data = Numo::SFloat.new(8, 8).rand
      svg = described_class.specshow(data, sr: 44_100, hop_length: 256, x_axis: :frames, y_axis: :mel, cmap: :gray, width: 320, height: 180)

      expect(svg).to include("data-x-axis='frames'")
      expect(svg).to include("data-y-axis='mel'")
      expect(svg).to include("width='320'")
    end
  end

  describe ".waveshow" do
    it "writes waveform SVG" do
      signal = Numo::SFloat.cast(Array.new(1024) { |idx| Math.sin((2.0 * Math::PI * idx) / 128.0) })
      Dir.mktmpdir do |dir|
        path = File.join(dir, "wave.svg")
        svg = described_class.waveshow(signal, output: path)

        expect(svg).to include("<svg")
        expect(File.exist?(path)).to be(true)
      end
    end

    it "uses envelope paths and split channels" do
      stereo = Array.new(1024) { |idx| [Math.sin(idx / 10.0), Math.cos(idx / 10.0)] }
      svg = described_class.waveshow(stereo, channels: :split)

      expect(svg).to include("<path")
      expect(svg).to include("data-channels='split'")
    end
  end
end
