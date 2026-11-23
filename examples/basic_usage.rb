#!/usr/bin/env ruby
# frozen_string_literal: true

# Run with: bundle exec ruby examples/basic_usage.rb

require 'bundler/setup'
require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'zsv'

sample_csv = <<~CSV
  id,name,email,age
  1,Alice,alice@example.com,30
  2,Bob,bob@example.com,25
  3,Charlie,charlie@example.com,35
CSV

dir = Dir.mktmpdir
at_exit { FileUtils.remove_entry(dir) }
path = File.join(dir, 'sample.csv')
File.write(path, sample_csv)

puts '=== 1. Parse a String ==='
p ZSV.parse(sample_csv)

puts "\n=== 2. Rows as Hashes ==="
ZSV.parse(sample_csv, headers: true).each do |row|
  puts "#{row['name']} (#{row['age']}) - #{row['email']}"
end

puts "\n=== 3. Stream a file ==="
ZSV.foreach(path, headers: true) { |row| puts "Processing user: #{row['name']}" }

puts "\n=== 4. Enumerator: no block, lazy, with_index ==="
adults = ZSV.foreach(path, headers: true).lazy.select { |row| row['age'].to_i >= 30 }.map { |row| row['name'] }
p adults.first(2)
ZSV.foreach(path).with_index(1) { |row, line| puts "#{line}: #{row.first}" }

puts "\n=== 5. Parser: shift, rewind, close ==="
parser = ZSV.open(path, headers: true)
puts "First row:    #{parser.shift.inspect}"
puts "Headers:      #{parser.headers.inspect}"
parser.rewind
puts "After rewind: #{parser.shift.inspect}"
parser.close

puts "\n=== 6. Block form closes the parser ==="
puts "Total rows: #{ZSV.open(path, &:count)}"

puts "\n=== 7. An IO is read as rows are consumed ==="
p ZSV.new(StringIO.new("a\tb\n1\t2\n"), col_sep: "\t").read

puts "\n=== 8. Strict parsing raises like CSV ==="
begin
  ZSV.parse(%(a,b\n1,x"y\n), liberal_parsing: false)
rescue ZSV::MalformedCSVError => e
  puts "#{e.class}: #{e.message} (line_number: #{e.line_number})"
end
puts "Lenient default: #{ZSV.parse(%(a,b\n1,x"y\n)).inspect}"
