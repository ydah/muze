# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/clean"
require_relative "benchmarks/quality_metrics"

RSpec::Core::RakeTask.new(:spec)

directory "ext/muze"

desc "Compile optional C extension"
task :compile do
  Dir.chdir("ext/muze") do
    ruby "extconf.rb"
    sh "make"
  end
end

desc "Run quality/performance benchmarks and compare with baseline"
task :bench do
  Muze::Benchmarks::QualityMetrics.run(
    output_path: ENV.fetch("MUZE_BENCH_OUTPUT", Muze::Benchmarks::QualityMetrics::DEFAULT_OUTPUT_PATH),
    baseline_path: ENV.fetch("MUZE_BENCH_BASELINE", Muze::Benchmarks::QualityMetrics::DEFAULT_BASELINE_PATH),
    fail_on_regression: ENV.fetch("MUZE_BENCH_FAIL_ON_REGRESSION", "1") != "0",
    update_baseline: ENV.fetch("MUZE_BENCH_UPDATE_BASELINE", "0") == "1"
  )
end

task default: :spec
