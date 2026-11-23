# frozen_string_literal: true

# Parsing throughput of ZSV against Ruby's CSV, on fixed generated datasets.
#
#   bundle exec ruby benchmark/parse_bench.rb
#
# BENCH_TIME / BENCH_WARMUP set the seconds measured per report (default 5 / 2),
# BENCH_JSON=parse.json also writes the numbers to benchmark/results/parse.json.
#
# Both parsers do the same work in each comparison: every row is yielded to a
# block and dropped. ZSV returns "" where CSV returns nil and its strings are
# frozen; with headers ZSV builds a Hash per row and CSV a CSV::Row, so the
# Hash that CSV::Row#to_h builds is reported as well.

require_relative 'support'
require 'benchmark/ips'

TIME = Float(ENV.fetch('BENCH_TIME', 5))
WARMUP = Float(ENV.fetch('BENCH_WARMUP', 2))

def compare(title, megabytes, reports)
  puts "=== #{title} ==="
  job = Benchmark.ips do |x|
    x.config(time: TIME, warmup: WARMUP)
    reports.each { |label, work| x.report(label, &work) }
    x.compare!
  end

  entries = job.entries.to_h { |entry| [entry.label, entry.stats.central_tendency] }
  baseline = entries.fetch(reports.keys.first)
  entries.map do |label, ips|
    { scenario: title, parser: label, ips: ips.round(3), mb_per_s: (ips * megabytes).round(1),
      speedup: (ips / baseline).round(2) }
  end
end

BenchSupport.print_environment
BenchSupport::DATASETS.each_key do |name|
  puts BenchSupport.describe_dataset(name)
  abort "ZSV and CSV disagree on #{name}: the comparison would be meaningless" unless BenchSupport.same_rows?(
    BenchSupport.dataset(name)
  )
end
puts

results = []

BenchSupport::DATASETS.each_key do |name|
  path = BenchSupport.dataset(name)
  megabytes = File.size(path) / 1024.0 / 1024.0

  results.concat(
    compare("foreach, #{BenchSupport.describe_dataset(name)}", megabytes,
            'CSV.foreach' => -> { CSV.foreach(path) { |row| row } },
            'ZSV.foreach' => -> { ZSV.foreach(path) { |row| row } })
  )
end

plain = BenchSupport.dataset(:plain)
plain_megabytes = File.size(plain) / 1024.0 / 1024.0

results.concat(
  compare('foreach with headers: true, plain', plain_megabytes,
          'CSV.foreach (CSV::Row)' => -> { CSV.foreach(plain, headers: true) { |row| row } },
          'CSV.foreach (to_h)' => -> { CSV.foreach(plain, headers: true, &:to_h) },
          'ZSV.foreach (Hash)' => -> { ZSV.foreach(plain, headers: true) { |row| row } })
)

plain_string = File.read(plain)
results.concat(
  compare('parse a String into an Array of rows, plain', plain_megabytes,
          'CSV.parse' => -> { CSV.parse(plain_string) },
          'ZSV.parse' => -> { ZSV.parse(plain_string) })
)

results.concat(
  compare('strict parsing (liberal_parsing: false), quoted', File.size(BenchSupport.dataset(:quoted)) / 1024.0 / 1024.0,
          'CSV.foreach' => -> { CSV.foreach(BenchSupport.dataset(:quoted)) { |row| row } },
          'ZSV.foreach strict' => lambda {
            ZSV.foreach(BenchSupport.dataset(:quoted), liberal_parsing: false) { |row| row }
          })
)

puts '=== Summary ==='
results.each do |result|
  puts format('%-58<scenario>.58s %-24<parser>s %10.2<ips>f i/s %8.1<mb_per_s>f MB/s %6.2<speedup>fx', result)
end

BenchSupport.write_json('parse', results)
