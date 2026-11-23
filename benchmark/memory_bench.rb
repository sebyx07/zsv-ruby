# frozen_string_literal: true

# Memory use of ZSV against Ruby's CSV, on a fixed generated dataset.
#
#   bundle exec ruby benchmark/memory_bench.rb
#
# BENCH_JSON=memory.json also writes the numbers to benchmark/results/memory.json.
#
# Every measurement runs in its own forked process, so neither parser inherits
# the heap the other one grew (needs fork: Linux or macOS). Reported per scenario:
#
#   peak RSS      growth of the process high-water mark while parsing
#   allocations   Ruby objects allocated (GC.stat total_allocated_objects)
#   retained      Ruby heap slots still live after a full GC with the rows held
#
# "streaming" drops every row; "holding" keeps all rows in an Array.

require_relative 'support'

SCENARIOS = {
  'streaming' => {
    'CSV.foreach' => ->(path) { CSV.foreach(path) { |row| row } },
    'ZSV.foreach' => ->(path) { ZSV.foreach(path) { |row| row } }
  },
  'holding all rows' => {
    'CSV.read' => ->(path) { CSV.read(path) },
    'ZSV.read' => ->(path) { ZSV.read(path) }
  },
  'holding all rows, headers: true' => {
    'CSV.read' => ->(path) { CSV.read(path, headers: true) },
    'ZSV.read' => ->(path) { ZSV.read(path, headers: true) }
  }
}.freeze

# Peak resident set size of this process in kilobytes
def peak_rss_kb
  status = File.read('/proc/self/status')
  Integer(status[/^VmHWM:\s+(\d+)/, 1])
rescue SystemCallError
  # No /proc (macOS): ru_maxrss is in bytes there
  Process.respond_to?(:getrusage) ? Process.getrusage.maxrss / 1024 : `ps -o rss= -p #{Process.pid}`.to_i
end

def measure(path, work)
  work.call(BenchSupport.dataset(:small)) # load the parser's code before measuring
  GC.start(full_mark: true, immediate_sweep: true)
  rss_before = peak_rss_kb
  allocated_before = GC.stat(:total_allocated_objects)
  live_before = GC.stat(:heap_live_slots)

  result = work.call(path)

  allocations = GC.stat(:total_allocated_objects) - allocated_before
  peak_rss_kb_growth = peak_rss_kb - rss_before
  GC.start(full_mark: true, immediate_sweep: true)
  retained = result ? GC.stat(:heap_live_slots) - live_before : 0

  { peak_rss_mb: (peak_rss_kb_growth / 1024.0).round(1), allocations: allocations, retained_slots: retained }
end

# Runs the measurement in a child process and returns its numbers
def measure_isolated(path, work)
  reader, writer = IO.pipe
  pid = fork do
    reader.close
    writer.write(JSON.generate(measure(path, work)))
    writer.close
    exit!(0)
  end
  writer.close
  output = reader.read
  Process.wait(pid)
  abort 'measurement process failed' unless $?.success? # rubocop:disable Style/SpecialGlobalVars

  JSON.parse(output, symbolize_names: true)
end

path = BenchSupport.dataset(:plain)

BenchSupport.print_environment
puts BenchSupport.describe_dataset(:plain)
# Checked in a child as well: a fork inherits the high-water mark of its
# parent, so the parent must not parse the dataset itself.
checker = fork { exit!(BenchSupport.same_rows?(path) ? 0 : 1) }
Process.wait(checker)
abort 'ZSV and CSV disagree on the dataset: the comparison would be meaningless' unless $?.success? # rubocop:disable Style/SpecialGlobalVars
puts

results = []
SCENARIOS.each do |scenario, parsers|
  puts "=== #{scenario} ==="
  parsers.each do |label, work|
    numbers = measure_isolated(path, work)
    results << { scenario: scenario, parser: label, **numbers }
    puts format('%-12<label>s peak RSS +%7.1<peak_rss_mb>f MB  %10<allocations>d allocations  ' \
                '%9<retained_slots>d retained slots', label: label, **numbers)
  end
  puts
end

BenchSupport.write_json('memory', results)
