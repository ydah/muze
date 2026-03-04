# frozen_string_literal: true

require_relative "lib/muze/version"

Gem::Specification.new do |spec|
  spec.name = "muze"
  spec.version = Muze::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Ruby audio feature extraction toolkit inspired by librosa"
  spec.description = "Muze provides audio loading, STFT, mel features, MFCC, rhythm analysis, and effects in Ruby."
  spec.homepage = "https://github.com/ydah/muze"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "numo-narray", "~> 0.9"
  spec.add_dependency "numo-pocketfft", ">= 0.4", "< 1.0"
  spec.add_dependency "wavify", "~> 0.1"
end
