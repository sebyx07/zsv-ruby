# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'rake_compiler_dock'

RSpec::Core::RakeTask.new(:spec)

# Precompiled gems are built with rake-compiler-dock, one docker image per
# platform, each holding a fat gem for every supported Ruby minor.
NATIVE_PLATFORMS = %w[
  x86_64-linux-gnu
  aarch64-linux-gnu
  x86_64-linux-musl
  aarch64-linux-musl
  x86_64-darwin
  arm64-darwin
].freeze
RakeCompilerDock.set_ruby_cc_version('>= 3.3')

GEMSPEC = Gem::Specification.load('zsv.gemspec')

Rake::ExtensionTask.new('zsv', GEMSPEC) do |ext|
  ext.lib_dir = 'lib/zsv'
  ext.cross_compile = true
  ext.cross_platform = NATIVE_PLATFORMS
  ext.cross_config_options << '--enable-cross-build'
end

task default: %i[compile spec]
task spec: :compile
task test: :spec
# Never package a vendored tree that does not match the pin (extconf.rb checks it for compile).
task build: 'zsv:check'

desc 'Run benchmarks'
task bench: :compile do
  Dir['benchmark/**/*_bench.rb'].each do |bench|
    puts "\n=== Running #{File.basename(bench)} ===\n"
    ruby bench
  end
end

desc 'Clean build artifacts'
task :clean do
  sh 'rm -rf tmp pkg lib/zsv/*.{so,bundle} lib/zsv/[0-9]* ext/zsv/*.{o,so,bundle}'
end

namespace :gem do
  desc "Build precompiled gems into pkg/ for #{NATIVE_PLATFORMS.join(', ')} (needs docker)"
  task native: NATIVE_PLATFORMS.map { |platform| "gem:native:#{platform}" }

  NATIVE_PLATFORMS.each do |platform|
    desc "Build the precompiled #{platform} gem into pkg/ (needs docker)"
    task "native:#{platform}" => 'zsv:check' do
      # The image's own Ruby, not the host's .ruby-version
      RakeCompilerDock.sh <<~SCRIPT, platform: platform
        export RBENV_VERSION="$(rbenv global)"
        bundle install --local || bundle install
        bundle exec rake native:#{platform} gem
      SCRIPT
    end
  end
end

# Releases are CI-only: merging a lib/zsv/version.rb bump makes release.yml publish and tag.
Rake::Task['release'].clear
desc 'Disabled: releases are published by CI (see RELEASE.md)'
task :release do
  abort 'Releases are published by CI: merge a lib/zsv/version.rb bump (see RELEASE.md).'
end
