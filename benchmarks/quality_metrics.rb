# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "time"

require_relative "../lib/muze"
require_relative "support/fixture_library"

module Muze
  module Benchmarks
    # Quality and performance benchmark runner with baseline comparison.
    module QualityMetrics
      module_function

      DEFAULT_OUTPUT_PATH = "benchmarks/reports/latest.json"
      DEFAULT_BASELINE_PATH = "benchmarks/baseline.json"
      DEFAULT_ITERATIONS = 3

      METRIC_DEFINITIONS = {
        "istft_reconstruction_error" => {
          unit: "rmse",
          direction: "lower",
          max_regression_ratio: 1.20
        },
        "time_stretch_processing_seconds" => {
          unit: "seconds_per_fixture",
          direction: "lower",
          max_regression_ratio: 4.00
        },
        "pitch_shift_processing_seconds" => {
          unit: "seconds_per_fixture",
          direction: "lower",
          max_regression_ratio: 4.00
        }
      }.freeze

      # @param output_path [String]
      # @param baseline_path [String]
      # @param fail_on_regression [Boolean]
      # @param update_baseline [Boolean]
      # @return [Hash]
      def run(output_path:, baseline_path:, fail_on_regression:, update_baseline:)
        fixtures = Muze::Benchmarks::FixtureLibrary.build
        metrics = collect_metrics(fixtures)
        baseline_metrics = load_baseline_metrics(baseline_path)
        regressions = detect_regressions(metrics, baseline_metrics)

        report = {
          generated_at: Time.now.utc.iso8601,
          ruby_version: RUBY_VERSION,
          ruby_platform: RUBY_PLATFORM,
          fixture_names: fixtures.keys,
          baseline_path: baseline_path,
          metrics: metrics,
          regressions: regressions
        }

        write_json(output_path, report)
        update_baseline_file(baseline_path, metrics) if update_baseline

        if fail_on_regression && !regressions.empty?
          raise Muze::Error, format_regression_error(regressions)
        end

        report
      end

      # @param fixtures [Hash{String => Numo::SFloat}]
      # @return [Hash]
      def collect_metrics(fixtures)
        {
          "istft_reconstruction_error" => metric_entry(
            value: average_istft_error(fixtures),
            definition: METRIC_DEFINITIONS.fetch("istft_reconstruction_error")
          ),
          "time_stretch_processing_seconds" => metric_entry(
            value: average_runtime_per_fixture(fixtures) { |signal| Muze.time_stretch(signal, rate: 1.25) },
            definition: METRIC_DEFINITIONS.fetch("time_stretch_processing_seconds")
          ),
          "pitch_shift_processing_seconds" => metric_entry(
            value: average_runtime_per_fixture(fixtures) { |signal| Muze.pitch_shift(signal, sr: 22_050, n_steps: 4.0) },
            definition: METRIC_DEFINITIONS.fetch("pitch_shift_processing_seconds")
          )
        }
      end
      private_class_method :collect_metrics

      # @param value [Float]
      # @param definition [Hash]
      # @return [Hash]
      def metric_entry(value:, definition:)
        {
          value: value,
          unit: definition.fetch(:unit),
          direction: definition.fetch(:direction),
          max_regression_ratio: definition.fetch(:max_regression_ratio)
        }
      end
      private_class_method :metric_entry

      # @param fixtures [Hash{String => Numo::SFloat}]
      # @return [Float]
      def average_istft_error(fixtures)
        errors = fixtures.values.map do |signal|
          stft_matrix = Muze.stft(signal, n_fft: 1024, hop_length: 256)
          reconstructed = Muze.istft(stft_matrix, hop_length: 256, length: signal.size)
          delta = signal - reconstructed
          Math.sqrt((delta * delta).mean.to_f)
        end

        errors.sum / errors.size.to_f
      end
      private_class_method :average_istft_error

      # @param fixtures [Hash{String => Numo::SFloat}]
      # @yieldparam signal [Numo::SFloat]
      # @return [Float]
      def average_runtime_per_fixture(fixtures)
        fixtures.each_value { |signal| yield(signal) }
        elapsed = measure_elapsed do
          DEFAULT_ITERATIONS.times do
            fixtures.each_value { |signal| yield(signal) }
          end
        end

        elapsed / (DEFAULT_ITERATIONS.to_f * fixtures.size)
      end
      private_class_method :average_runtime_per_fixture

      # @yieldreturn [void]
      # @return [Float]
      def measure_elapsed
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      end
      private_class_method :measure_elapsed

      # @param baseline_path [String]
      # @return [Hash]
      def load_baseline_metrics(baseline_path)
        return {} unless File.exist?(baseline_path)

        baseline_json = JSON.parse(File.read(baseline_path))
        baseline_json.fetch("metrics", {})
      rescue JSON::ParserError
        {}
      end
      private_class_method :load_baseline_metrics

      # @param current_metrics [Hash]
      # @param baseline_metrics [Hash]
      # @return [Array<Hash>]
      def detect_regressions(current_metrics, baseline_metrics)
        current_metrics.filter_map do |metric_name, current|
          baseline = baseline_metrics[metric_name]
          next unless baseline

          baseline_value = baseline.fetch("value").to_f
          ratio = current.fetch(:max_regression_ratio)
          max_allowed_value = baseline_value * ratio
          current_value = current.fetch(:value)
          next unless current_value > max_allowed_value

          {
            metric: metric_name,
            baseline_value: baseline_value,
            current_value: current_value,
            max_allowed_value: max_allowed_value,
            max_regression_ratio: ratio
          }
        end
      end
      private_class_method :detect_regressions

      # @param path [String]
      # @param report [Hash]
      # @return [void]
      def write_json(path, report)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report))
      end
      private_class_method :write_json

      # @param baseline_path [String]
      # @param metrics [Hash]
      # @return [void]
      def update_baseline_file(baseline_path, metrics)
        FileUtils.mkdir_p(File.dirname(baseline_path))
        payload = {
          generated_at: Time.now.utc.iso8601,
          ruby_version: RUBY_VERSION,
          metrics: metrics.transform_values do |entry|
            {
              value: entry.fetch(:value),
              unit: entry.fetch(:unit),
              direction: entry.fetch(:direction),
              max_regression_ratio: entry.fetch(:max_regression_ratio)
            }
          end
        }
        File.write(baseline_path, JSON.pretty_generate(payload))
      end
      private_class_method :update_baseline_file

      # @param regressions [Array<Hash>]
      # @return [String]
      def format_regression_error(regressions)
        lines = regressions.map do |regression|
          format(
            "%<metric>s regressed: current=%<current>.8f baseline=%<baseline>.8f limit=%<limit>.8f (x%<ratio>.2f)",
            metric: regression.fetch(:metric),
            current: regression.fetch(:current_value),
            baseline: regression.fetch(:baseline_value),
            limit: regression.fetch(:max_allowed_value),
            ratio: regression.fetch(:max_regression_ratio)
          )
        end

        "Benchmark regression detected:\n#{lines.join("\n")}"
      end
      private_class_method :format_regression_error
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    output_path: Muze::Benchmarks::QualityMetrics::DEFAULT_OUTPUT_PATH,
    baseline_path: Muze::Benchmarks::QualityMetrics::DEFAULT_BASELINE_PATH,
    fail_on_regression: false,
    update_baseline: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby benchmarks/quality_metrics.rb [options]"

    opts.on("--output PATH", "Output JSON path (default: #{options[:output_path]})") do |path|
      options[:output_path] = path
    end

    opts.on("--baseline PATH", "Baseline JSON path (default: #{options[:baseline_path]})") do |path|
      options[:baseline_path] = path
    end

    opts.on("--fail-on-regression", "Exit with non-zero code on baseline regression") do
      options[:fail_on_regression] = true
    end

    opts.on("--update-baseline", "Write current metrics into baseline JSON") do
      options[:update_baseline] = true
    end
  end.parse!

  begin
    report = Muze::Benchmarks::QualityMetrics.run(**options)
    puts "Benchmark report written to #{options[:output_path]}"
    puts "No regressions detected" if report.fetch(:regressions).empty?
  rescue Muze::Error => e
    warn e.message
    exit(1)
  end
end
