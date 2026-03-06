# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "example scripts" do
  project_root = File.expand_path("../..", __dir__)
  examples_dir = File.join(project_root, "examples")
  mono_path = File.join(project_root, "spec/fixtures/sine_440_mono_44100.wav")
  stereo_path = File.join(project_root, "spec/fixtures/sine_440_stereo_44100.wav")

  define_method :run_example do |script_name, *args|
    Open3.capture3(
      RbConfig.ruby,
      File.join(examples_dir, script_name),
      *args,
      chdir: project_root
    )
  end

  define_method :command_output do |status, stdout, stderr|
    [
      "exit status: #{status.exitstatus}",
      ("stdout:\n#{stdout}" unless stdout.empty?),
      ("stderr:\n#{stderr}" unless stderr.empty?)
    ].compact.join("\n")
  end

  define_method :extract_number do |stdout, pattern|
    match = stdout.match(pattern)
    match && match[1].to_f
  end

  it "renders a mel spectrogram from the load_and_specshow example" do
    Dir.mktmpdir("muze-example-load") do |dir|
      output_path = File.join(dir, "mel.svg")
      stdout, stderr, status = run_example("load_and_specshow.rb", mono_path, output_path)

      expect(status.success?).to be(true), command_output(status, stdout, stderr)
      expect(stderr).to eq("")
      expect(stdout).to include("Sample rate: 22050 Hz")
      expect(stdout).to include("Mel shape: 128 x")
      expect(stdout).to include("Wrote: #{output_path}")
      expect(File.read(output_path)).to include("<svg")
    end
  end

  it "renders chroma SVG and identifies A for the sine-wave fixture" do
    Dir.mktmpdir("muze-example-chroma") do |dir|
      output_path = File.join(dir, "chroma.svg")
      stdout, stderr, status = run_example("chroma_svg.rb", stereo_path, output_path)

      expect(status.success?).to be(true), command_output(status, stdout, stderr)
      expect(stderr).to eq("")
      expect(stdout).to include("Chroma shape: 12 x")
      expect(stdout).to include("Dominant pitch class: A")
      expect(stdout).to include("Wrote: #{output_path}")
      expect(File.read(output_path)).to include("<svg")
    end
  end

  it "reports beat-tracking metrics without crashing" do
    stdout, stderr, status = run_example("beat_tracking.rb", mono_path)

    expect(status.success?).to be(true), command_output(status, stdout, stderr)
    expect(stderr).to eq("")
    expect(extract_number(stdout, /Estimated tempo: ([0-9.]+) BPM/)).to be > 0
    expect(extract_number(stdout, /Detected onsets: ([0-9.]+)/)).to be >= 1
    expect(extract_number(stdout, /Detected beats: ([0-9.]+)/)).to be >= 1
  end

  it "reports stable feature values for the sine-wave fixture" do
    stdout, stderr, status = run_example("feature_report.rb", mono_path)

    expect(status.success?).to be(true), command_output(status, stdout, stderr)
    expect(stderr).to eq("")
    expect(stdout).to include("MFCC shape: 13 x")
    expect(stdout).to include("Delta shape: 13 x")
    expect(extract_number(stdout, /Mean spectral centroid: ([0-9.]+) Hz/)).to be_between(430.0, 470.0)
    expect(extract_number(stdout, /Mean RMS: ([0-9.]+)/)).to be_between(0.5, 0.7)
  end

  it "separates harmonic and percussive content and renders all HPSS outputs" do
    Dir.mktmpdir("muze-example-hpss") do |dir|
      output_prefix = File.join(dir, "split")
      stdout, stderr, status = run_example("hpss_demo.rb", mono_path, output_prefix)

      expect(status.success?).to be(true), command_output(status, stdout, stderr)
      expect(stderr).to eq("")

      harmonic_rms = extract_number(stdout, /Harmonic RMS: ([0-9.]+)/)
      percussive_rms = extract_number(stdout, /Percussive RMS: ([0-9.]+)/)

      expect(harmonic_rms).to be > percussive_rms

      %w[harmonic_wave percussive_wave harmonic_mel percussive_mel].each do |suffix|
        output_path = "#{output_prefix}_#{suffix}.svg"
        expect(stdout).to include("Wrote: #{output_path}")
        expect(File.read(output_path)).to include("<svg")
      end
    end
  end
end
