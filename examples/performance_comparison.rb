#!/usr/bin/env ruby
# frozen_string_literal: true

# A quick, single-run look at ZSV next to Ruby's CSV on one generated file.
# Run with: bundle exec ruby examples/performance_comparison.rb
#
# For numbers worth quoting use the benchmarks, which warm up, repeat and
# isolate memory measurements: bundle exec rake bench

require 'bundler/setup'
require 'csv'
require 'tmpdir'
require 'zsv'

ROWS = 100_000
COLUMNS = 10
RUNS = 5

def seconds
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
end

def best_of(runs, &)
  Array.new(runs) { seconds(&) }.min
end

Dir.mktmpdir do |dir|
  path = File.join(dir, 'performance.csv')
  File.open(path, 'w') do |file|
    file.puts(Array.new(COLUMNS) { |column| "col#{column + 1}" }.join(','))
    ROWS.times { |row| file.puts(Array.new(COLUMNS) { |column| "value_#{row}_#{column}" }.join(',')) }
  end

  puts "#{ROWS} rows x #{COLUMNS} columns, #{File.size(path) / 1024} KB, best of #{RUNS} runs"
  puts RUBY_DESCRIPTION

  csv = best_of(RUNS) { CSV.foreach(path) { |row| row } }
  zsv = best_of(RUNS) { ZSV.foreach(path) { |row| row } }
  puts format('CSV.foreach  %<time>.3f s', time: csv)
  puts format('ZSV.foreach  %<time>.3f s  (%<ratio>.1fx)', time: zsv, ratio: csv / zsv)

  csv = best_of(RUNS) { CSV.foreach(path, headers: true) { |row| row } }
  zsv = best_of(RUNS) { ZSV.foreach(path, headers: true) { |row| row } }
  puts format('CSV.foreach headers: true  %<time>.3f s', time: csv)
  puts format('ZSV.foreach headers: true  %<time>.3f s  (%<ratio>.1fx)', time: zsv, ratio: csv / zsv)
end
