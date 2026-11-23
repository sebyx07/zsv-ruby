# frozen_string_literal: true

require 'bundler/setup'
require 'csv'
require 'fileutils'
require 'json'
require 'zsv'

# Shared by the benchmark scripts: fixed, reproducible datasets and the
# report of the environment the numbers were taken in.
#
# Datasets are generated from a fixed seed into tmp/benchmark (override with
# BENCH_DATA_DIR), so two runs — and two machines — parse identical bytes.
module BenchSupport
  DATA_DIR = ENV.fetch('BENCH_DATA_DIR', File.expand_path('../tmp/benchmark', __dir__))
  RESULTS_DIR = File.expand_path('results', __dir__)
  SEED = 20_240_101
  WORDS = %w[alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima].freeze

  # name => [rows, columns, quoted?]
  DATASETS = {
    small: [1_000, 5, false],
    plain: [100_000, 10, false],
    wide: [10_000, 100, false],
    quoted: [50_000, 8, true]
  }.freeze

  module_function

  # @param name [Symbol] a key of DATASETS
  # @return [String] path of the dataset, generated on first use
  def dataset(name)
    rows, columns, quoted = DATASETS.fetch(name)
    path = File.join(DATA_DIR, "#{name}-#{rows}x#{columns}-seed#{SEED}.csv")
    return path if File.exist?(path)

    FileUtils.mkdir_p(DATA_DIR)
    File.write("#{path}.part", generate(rows, columns, quoted))
    File.rename("#{path}.part", path)
    path
  end

  def generate(rows, columns, quoted)
    random = Random.new(SEED)
    lines = [Array.new(columns) { |column| "col#{column + 1}" }.join(',')]
    rows.times do |row|
      lines << Array.new(columns) { |column| field(random, row, column, quoted) }.join(',')
    end
    "#{lines.join("\n")}\n"
  end

  # Unquoted fields mix integers, decimals and words. Quoted datasets add,
  # in every third column, a separator, an escaped quote or a line break.
  def field(random, row, column, quoted)
    return quoted_field(random, row) if quoted && (column % 3).zero?

    case column % 4
    when 0 then row.to_s
    when 1 then "#{WORDS[random.rand(WORDS.size)]}_#{row}"
    when 2 then format('%.2f', random.rand * 10_000)
    else WORDS[random.rand(WORDS.size)]
    end
  end

  def quoted_field(random, row)
    word = WORDS[random.rand(WORDS.size)]
    case random.rand(3)
    when 0 then %("#{word}, #{row}")
    when 1 then %("say ""#{word}""")
    else %("#{word}\n#{row}")
    end
  end

  # Rows of both parsers in ZSV's shape, to prove they do the same work.
  def same_rows?(path)
    ZSV.read(path) == CSV.read(path, nil_value: '')
  end

  def describe_dataset(name)
    rows, columns, quoted = DATASETS.fetch(name)
    megabytes = File.size(dataset(name)) / 1024.0 / 1024.0
    format('%<name>s: %<rows>d rows x %<columns>d cols, %<mb>.1f MB%<quoted>s',
           name: name, rows: rows, columns: columns, mb: megabytes, quoted: quoted ? ', quoted fields' : '')
  end

  def environment
    {
      ruby: RUBY_DESCRIPTION,
      yjit: defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false,
      platform: RUBY_PLATFORM,
      zsv_gem: ZSV::VERSION,
      csv_gem: CSV::VERSION,
      cpu: cpu_model
    }
  end

  def cpu_model
    return `sysctl -n machdep.cpu.brand_string`.strip if RUBY_PLATFORM.include?('darwin')

    File.foreach('/proc/cpuinfo') { |line| return line.split(':', 2).last.strip if line.start_with?('model name') }
    'unknown'
  rescue SystemCallError
    'unknown'
  end

  def print_environment
    puts 'Environment'
    environment.each { |key, value| puts "  #{key.to_s.ljust(9)} #{value}" }
    puts
  end

  # Writes the results as JSON when BENCH_JSON names a file (relative names
  # go to benchmark/results/), for tooling that tracks them.
  def write_json(benchmark, results)
    target = ENV.fetch('BENCH_JSON', nil)
    return unless target

    path = File.expand_path(target, RESULTS_DIR)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(benchmark: benchmark, environment: environment, results: results))
    puts "Results written to #{path}"
  end
end
