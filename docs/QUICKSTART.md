# ZSV Quick Start

ZSV reads CSV with the [zsv](https://github.com/liquidaty/zsv) C library behind an API modelled on Ruby's `CSV`.

## Install

```ruby
# Gemfile
gem 'zsv'
```

```bash
bundle install   # or: gem install zsv
```

Needs Ruby 3.3 or newer. The gem builds a C extension when no precompiled one matches your platform, which takes a C compiler and `make`.

## Read a file

```ruby
require 'zsv'

# One row at a time, constant memory
ZSV.foreach("data.csv") do |row|
  row  # => ["1", "Alice", "30"]
end

# Rows as Hashes keyed by the header row
ZSV.foreach("data.csv", headers: true) do |row|
  puts "#{row['name']} is #{row['age']}"
end

# Everything at once
rows = ZSV.read("data.csv")
```

Without a block `ZSV.foreach` returns an Enumerator:

```ruby
ZSV.foreach("data.csv", headers: true).lazy
   .select { |row| row["age"].to_i >= 18 }
   .first(10)

ZSV.foreach("data.csv").each_with_index { |row, index| ... }
```

## Parse a String

```ruby
ZSV.parse("a,b,c\n1,2,3\n")
# => [["a", "b", "c"], ["1", "2", "3"]]

ZSV.parse("a|b\n1|2\n", col_sep: "|", headers: true)
# => [{"a" => "1", "b" => "2"}]

ZSV.parse_line("a,b,c")
# => ["a", "b", "c"]
```

## Read from an IO

```ruby
ZSV.new($stdin).each { |row| ... }

File.open("data.csv") do |file|
  parser = ZSV.new(file, headers: true)
  first = parser.shift
end
```

## Pull rows yourself

```ruby
ZSV.open("data.csv", headers: true) do |parser|
  first = parser.shift
  parser.headers   # => ["id", "name", "age"]
  rest = parser.read
  parser.rewind    # start over
end                # closed here
```

## Options

```ruby
ZSV.foreach("data.tsv", col_sep: "\t") { |row| ... }
ZSV.foreach("report.csv", skip_lines: 2, headers: true) { |row| ... }  # drop 2 leading rows
ZSV.read("data.csv", headers: %w[id name age])                         # names for a file without a header row
ZSV.read("latin1.csv", encoding: "ISO-8859-1")
```

The full list is in the [API reference](API_REFERENCE.md#options). An option ZSV does not know raises `ArgumentError`.

## Coming from CSV

Most reading code works after replacing `CSV.` with `ZSV.`. What to check:

- Empty unquoted fields are `""`, not `nil`.
- Rows are plain `Array`s and `Hash`es of frozen Strings, not `CSV::Row` / `CSV::Table`.
- Malformed quoting does not raise by default. Pass `liberal_parsing: false` to get `ZSV::MalformedCSVError` with `CSV`'s messages and line numbers:

  ```ruby
  ZSV.parse(%(a,b\n1,x"y\n), liberal_parsing: false)
  # ZSV::MalformedCSVError: Illegal quoting in line 2.
  ```

- No converters, no writing, single-character `col_sep`, `"` as the only quote character.

Every difference is listed in the [API reference](API_REFERENCE.md#differences-from-csv).

## Working on the gem

```bash
git clone https://github.com/sebyx07/zsv-ruby.git
cd zsv-ruby
bin/setup                              # Ruby, gems, C extension
bundle exec rspec                      # tests
bundle exec ruby examples/basic_usage.rb
bundle exec rake bench                 # benchmarks against CSV
```

The benchmarks generate their datasets from a fixed seed into `tmp/benchmark/`, print the environment they ran in, and take `BENCH_TIME`, `BENCH_WARMUP` and `BENCH_JSON` (see the headers of `benchmark/parse_bench.rb` and `benchmark/memory_bench.rb`).
