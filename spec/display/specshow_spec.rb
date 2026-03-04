# frozen_string_literal: true

require "tmpdir"

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
        path = File.join(dir, "spectrogram.svg")
        described_class.specshow(data, output: path)

        expect(File.exist?(path)).to be(true)
      end
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
  end
end
