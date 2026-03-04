# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/clean"

RSpec::Core::RakeTask.new(:spec)

directory "ext/muze"

desc "Compile optional C extension"
task :compile do
  Dir.chdir("ext/muze") do
    ruby "extconf.rb"
    sh "make"
  end
end

task default: :spec
