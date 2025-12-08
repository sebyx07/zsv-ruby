# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

# Only load rake-compiler for MRI Ruby
if RUBY_PLATFORM == 'java'
  # JRuby - no C extension to compile
  task default: :spec
  task test: :spec

  desc 'Run benchmarks'
  task :bench do
    Dir['benchmark/**/*_bench.rb'].each do |bench|
      puts "\n=== Running #{File.basename(bench)} ===\n"
      ruby bench
    end
  end

  desc 'Clean build artifacts'
  task :clean do
    sh 'rm -rf tmp pkg'
  end

  # Dummy compile task for JRuby
  task :compile do
    puts 'JRuby detected - no C extension to compile'
  end
else
  require 'rake/extensiontask'

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
end
