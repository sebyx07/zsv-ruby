# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/extensiontask'

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new('zsv') do |ext|
  ext.lib_dir = 'lib/zsv'
end

task default: %i[compile spec]
task spec: :compile
task test: :spec

desc 'Run benchmarks'
task bench: :compile do
  Dir['benchmark/**/*_bench.rb'].each do |bench|
    puts "\n=== Running #{File.basename(bench)} ===\n"
    ruby bench
  end
end

desc 'Clean build artifacts'
task :clean do
  sh 'rm -rf tmp pkg lib/zsv/*.{so,bundle} ext/zsv/*.{o,so,bundle}'
end

namespace :release do
  desc 'Tag the current ZSV::VERSION and push it (CI publishes the gem)'
  task :tag do
    require_relative 'lib/zsv/version'
    version = ZSV::VERSION
    tag = "v#{version}"

    abort 'Working tree is not clean. Commit the version bump and CHANGELOG first.' \
      unless `git status --porcelain`.strip.empty?

    abort "Tag #{tag} already exists." unless `git tag -l #{tag}`.strip.empty?

    puts "Tagging #{tag} and pushing to origin..."
    sh "git tag -a #{tag} -m 'Release #{tag}'"
    sh "git push origin #{tag}"
    puts "Pushed #{tag}. The Release workflow will publish #{version} to RubyGems."
  end
end
