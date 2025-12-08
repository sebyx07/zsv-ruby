# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

# Only load rake-compiler for MRI Ruby
if RUBY_PLATFORM == 'java'
  # JRuby - build JNI extension
  desc 'Build JNI extension for JRuby'
  task :compile do
    Dir.chdir('ext/zsv/java') do
      ruby 'extconf.rb'
    end
  end

  task default: %i[compile spec]
  task spec: :compile
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
    sh 'rm -rf tmp pkg ext/zsv/vendor lib/zsv/java/*.{so,dylib} lib/zsv/java/classes'
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
