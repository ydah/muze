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

    it "can return only the SVG fragment" do
      data = Numo::SFloat.new(4, 4).rand
      fragment = described_class.specshow(data, fragment: true)

      expect(fragment).to start_with("<g ")
      expect(fragment).not_to include("<svg")
    end

    it "can render spectrogram cells as an embedded image" do
      data = Numo::SFloat.new(16, 16).rand
      svg = described_class.specshow(data, render: :image)

      expect(svg).to include("<image")
      expect(svg).to include("data:image/bmp;base64")
      expect(svg).to include("data-render='image'")
    end

    it "rejects invalid display parameters" do
      expect do
        described_class.specshow(Numo::SFloat[[1.0]], sr: 0)
      end.to raise_error(Muze::ParameterError, /sr/)

      expect do
        described_class.specshow(Numo::SFloat[[1.0]], vmin: 2.0, vmax: 1.0)
      end.to raise_error(Muze::ParameterError, /vmin/)

      expect do
        described_class.specshow(Numo::SFloat[[1.0]], render: :bad)
      end.to raise_error(Muze::ParameterError, /render/)
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

    it "validates waveform display input" do
      expect do
        described_class.waveshow([0.0, Float::NAN])
      end.to raise_error(Muze::ParameterError, /finite/)

      expect do
        described_class.waveshow([0.0], normalize: :yes)
      end.to raise_error(Muze::ParameterError, /normalize/)
    end
  end

  describe ".onsetshow" do
    it "renders an onset envelope as SVG bars" do
      svg = described_class.onsetshow([0.0, 1.0, 0.5], sr: 22_050, hop_length: 512)

      expect(svg).to include("data-kind='onset'")
      expect(svg.scan("<rect").length).to be >= 4
    end

    it "validates onset display normalization" do
      expect do
        described_class.onsetshow([0.0], normalize: :yes)
      end.to raise_error(Muze::ParameterError, /normalize/)
    end
  end
end
