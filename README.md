# zsv

[![CI](https://github.com/sebyx07/zsv-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/sebyx07/zsv-ruby/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/zsv)](https://rubygems.org/gems/zsv)
[![Gem Downloads](https://img.shields.io/gem/dt/zsv)](https://rubygems.org/gems/zsv)
[![License](https://img.shields.io/github/license/sebyx07/zsv-ruby)](LICENSE)
[![Maintained by developerz.ai](https://img.shields.io/badge/maintained%20by-developerz.ai-6f42c1)](https://developerz.ai)

A fast CSV parser for Ruby with the reading API of the `CSV` standard library. The parsing is done by [zsv](https://github.com/liquidaty/zsv), a SIMD-accelerated C library, through a native extension.

```ruby
require 'zsv'

ZSV.foreach('data.csv', headers: true) do |row|
  puts row['name']
end
```

- **Familiar**: `ZSV.foreach`, `ZSV.parse`, `ZSV.read`, `ZSV.open`, `ZSV::Parser#shift` / `#each`, with the option names `CSV` uses.
- **Streaming**: rows are produced as the input is read; a file is never loaded whole.
- **Checked against `CSV`**: the test suite compares rows with the standard library's for the same input and option. The [intended differences](#differences-from-csv) are few and listed.
- **Self-contained**: the zsv source ships inside the gem, pinned by SHA-256. Installing downloads nothing beyond the gem and needs no system library.

It parses; it does not write CSV. For generating CSV, converters, or `CSV::Table`, keep using `csv`.

## Install

```ruby
# Gemfile
gem 'zsv'
```

or `gem install zsv`.

- **Precompiled gems** are published, from 1.4.4 on, for Linux (x86_64 and aarch64, glibc and musl) and macOS (x86_64 and arm64): no compiler needed. They are built for the baseline CPU of each architecture (SSE2 / NEON).
- **Everywhere else** the source gem compiles on install. That needs a C compiler and `make`, and nothing from the network: the zsv C source is inside the gem. A source build also targets the baseline CPU (SSE2 / NEON), so a binary built on one machine (a Docker image built in CI, for example) runs on any other machine of the same architecture. When the code runs only where it was built, you can build for that machine's CPU instead (`-march=native`):

  ```bash
  gem install zsv --platform ruby -- --enable-native
  # or ZSV_NATIVE=1 gem install zsv --platform ruby; with Bundler:
  bundle config set --local build.zsv --enable-native
  bundle config set --local force_ruby_platform true
  ```

Supported Rubies and platforms are the ones CI tests: see the matrix in [`.github/workflows/ci.yml`](.github/workflows/ci.yml). The Ruby floor is `required_ruby_version` in [`zsv.gemspec`](zsv.gemspec). Windows is not supported yet.

**Versioning.** The gem version is the version of the zsv library it wraps: gem `1.4.4` ships zsv `1.4.4`. A gem-only release adds a fourth segment (`1.4.4.1`).

## Usage

### Files

```ruby
# Stream rows; nothing is kept
ZSV.foreach('data.csv') { |row| p row }        # row is an Array of Strings

# Without a block: an Enumerator
ZSV.foreach('data.csv').with_index { |row, i| ... }
ZSV.foreach('data.csv').lazy.select { |row| row[2] == 'paid' }.first(10)

# Everything at once
rows = ZSV.read('data.csv')                    # => [["a", "b"], ["1", "2"]]
```

### Strings

```ruby
ZSV.parse("a,b\n1,2\n")                        # => [["a", "b"], ["1", "2"]]
ZSV.parse_line('a,"b,c"')                      # => ["a", "b,c"]
```

### Headers

```ruby
ZSV.parse("name,age\nAda,36\n", headers: true)
# => [{"name" => "Ada", "age" => "36"}]

# Supply the headers yourself (the first row is then data)
ZSV.foreach('data.csv', headers: %w[id name email]) { |row| row['email'] }
```

With headers each row is a plain `Hash`, not a `CSV::Row`.

### A parser object

```ruby
ZSV.open('data.csv', headers: true) do |csv|   # closed when the block returns
  first = csv.shift                            # one row, or nil at the end
  csv.headers                                  # => ["name", "age"] (nil until the first row is read)
  csv.each { |row| ... }                       # the rest
  csv.rewind
end

parser = ZSV::Parser.new(io)                   # any object with #read; or a path, a Pathname, CSV data
parser.each_slice(1_000) { |batch| ... }       # Enumerable
parser.close
```

`ZSV::Parser.new` guesses whether a String is CSV data or a path (see the [API reference](docs/API_REFERENCE.md)); `ZSV::Parser.from_string` and `ZSV::Parser.from_path` do not guess.

### Options

The common ones; the complete list, with defaults and every accepted value, is in [`docs/API_REFERENCE.md`](docs/API_REFERENCE.md).

| Option | Meaning |
|---|---|
| `headers` | `true`: the first row names the fields. An `Array` or a CSV line: your own names |
| `col_sep` | Column separator, one ASCII character (`"\t"`, `";"`, `"|"`) |
| `skip_lines` | Number of leading rows to drop |
| `liberal_parsing` | `false`: raise `ZSV::MalformedCSVError` on malformed input, as `CSV` does by default |
| `encoding` | Encoding the returned Strings are labelled with (no transcoding) |

```ruby
ZSV.foreach('data.tsv', col_sep: "\t", headers: true) { |row| ... }
```

An option the gem does not implement raises `ArgumentError`; nothing is silently ignored.

### Errors

`ZSV::Error` is the base class. `ZSV::MalformedCSVError` and `ZSV::InvalidEncodingError` mirror `CSV`'s. A missing file raises the usual `Errno::ENOENT`.

## Differences from `CSV`

The suite compares ZSV's rows with `CSV`'s for the same input. These differences are intended:

| | `CSV` | `ZSV` |
|---|---|---|
| Malformed input | raises by default (`liberal_parsing: false`) | **lenient by default**: zsv never rejects input. Pass `liberal_parsing: false` to validate like `CSV` and raise `ZSV::MalformedCSVError` |
| Empty unquoted field (`a,,b`) | `nil` | `""` |
| Row with headers | `CSV::Row`; `CSV.parse` returns a `CSV::Table` | a plain `Hash`; `ZSV.parse` returns an `Array` of them. With duplicate header names the first one wins, as in `CSV::Row#to_h` |
| Field Strings | mutable | frozen |
| UTF-8 BOM | kept unless `encoding: 'bom|utf-8'` | always stripped |
| `col_sep` | any String | one ASCII character |
| `quote_char` | any character | only `"` |
| `row_sep` | any String | always auto-detected (`\n`, `\r\n`, `\r`) |
| `skip_lines` | a pattern matching lines to skip | a number of leading rows to drop |
| `encoding` | can transcode (`'iso-8859-1:utf-8'`) | labels the returned Strings; no transcoding |
| Very wide rows | no limit | more than `max_columns` fields (1024 unless raised) raises `ZSV::MalformedCSVError` rather than dropping data |
| Very long rows | no limit | a row over `max_row_size` bytes (256 KiB unless raised) raises `ZSV::MalformedCSVError` rather than being cut short |
| Converters, `CSV::Table`, writing | yes | no: unsupported options raise `ArgumentError` |

[`docs/API_REFERENCE.md`](docs/API_REFERENCE.md) is the authoritative list.

## Performance

zsv scans input with SIMD instructions and the extension builds Ruby rows directly in C, so parsing is faster than the pure-Ruby `CSV`. How much depends on the shape of the data (row width, quoting), the options (rows as Hashes cost more than rows as Arrays), the CPU and the Ruby version, so this README does not carry a headline number.

**Current numbers are produced by CI**: the [Benchmarks workflow](https://github.com/sebyx07/zsv-ruby/actions/workflows/benchmark.yml) runs on every push to `main`, on x86_64 and arm64 Linux, and prints the full output in each run's summary, with the Ruby version and commit.

As a guide, across the maintainers' runs of `bundle exec rake bench` on x86_64 Linux, `ZSV.foreach` has typically been 3 to 4 times faster than `CSV.foreach`: a little over 2x on very wide rows, up to about 11 to 12x on heavily quoted data. `liberal_parsing: false` adds a validation pass in Ruby and lands near 2x. ZSV makes about half the allocations and holds a parsed file in noticeably less memory. These are ranges from a few machines, not a promise: the CI summaries and your own run are the reference.

Reproduce it on your own data and hardware:

```bash
git clone https://github.com/sebyx07/zsv-ruby && cd zsv-ruby
bin/setup
bundle exec rake bench      # benchmark/parse_bench.rb and benchmark/memory_bench.rb
BENCH_TIME=10 BENCH_JSON=parse.json bundle exec ruby benchmark/parse_bench.rb   # longer runs, JSON in benchmark/results/
```

Both sides of every comparison do the same work on the same generated, fixed-seed input, and the scripts abort if the two parsers disagree on the rows.

## Documentation

- [Quick start](docs/QUICKSTART.md)
- [API reference](docs/API_REFERENCE.md): every method, option, error and difference from `CSV`
- [`llms.txt`](llms.txt): the same reference condensed into one file for AI coding agents
- [Changelog](CHANGELOG.md)

## AI agents

**This project is maintained by [developerz.ai](https://developerz.ai).** Its maintainer agent triages issues, reviews every pull request, merges every pull request once its author marks it ready and CI passes, watches project health daily, follows new releases of the zsv C library, and opens release PRs. The policy is in [`.dz/maintainer/maintainer.yml`](.dz/maintainer/maintainer.yml). Breaking changes stay with the owner.

- **Using zsv in your app?** Point your agent at [`llms.txt`](llms.txt), the complete reference in one file (methods, options, differences from `CSV`, pitfalls). Paste this into your app's `CLAUDE.md` / `AGENTS.md`:
  ```markdown
  ## CSV parsing
  CSV files are read with the zsv gem (`ZSV.foreach`, `ZSV.parse`), not Ruby's CSV. Before editing that code read
  https://github.com/sebyx07/zsv-ruby/blob/main/llms.txt
  ```
- **Working on this repo?** [`CLAUDE.md`](CLAUDE.md) is the agent-instructions file (`AGENTS.md` is a symlink to it): invariants, commands, code map, how to verify a change, the release lane. [`ext/CLAUDE.md`](ext/CLAUDE.md) holds the rules for the C extension.
- **Claude Code**: commands in `.claude/commands/` (`/planx`, `/feature`, `/release`), skills in `.claude/skills/` (`verify-change`, `upgrade-zsv`, `debug-gc`), and a read-only reviewer subagent in `.claude/agents/` (`c-safety-reviewer`).
- **How the gem follows zsv**: once a month an agent runs `bin/zsv-upstream-check`; when zsv has a new release it reads the upstream changes, re-vendors the source, runs the suite, the sanitizers and the benchmarks before and after, and opens `chore: zsv X.Y.Z`. The next weekly release check then publishes gem `X.Y.Z`. The brief is [`.dz/schedules/upstream-zsv.md`](.dz/schedules/upstream-zsv.md).

## Development

```bash
bin/setup          # Ruby, gems, compile the extension (offline after the gems)
bin/check          # the gate CI runs: repo guards, RuboCop, clang-format, compile, RSpec
bin/check fast     # inner loop
bin/check asan     # the suite under AddressSanitizer + UBSan (Linux)
bin/console        # IRB with ZSV and CSV loaded
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md) (GitHub private vulnerability reporting), never a public issue. Releases are cut by merging a version bump: [RELEASE.md](RELEASE.md).

## License and credits

MIT, see [LICENSE](LICENSE). The bundled [zsv](https://github.com/liquidaty/zsv) library is by Liquidaty and also MIT-licensed; its license ships with the gem at `ext/zsv/vendor/zsv/LICENSE`.

## Star history

[![Star History Chart](https://api.star-history.com/svg?repos=sebyx07/zsv-ruby&type=Date)](https://star-history.com/#sebyx07/zsv-ruby&Date)
