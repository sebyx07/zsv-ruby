# ZSV - SIMD-Accelerated CSV Parser for Ruby ⚡

A drop-in replacement for Ruby's CSV stdlib that uses the [zsv](https://github.com/liquidaty/zsv) C library for 5-6x performance improvements via SIMD optimizations.

> 🤖 Built with [Claude Code](https://claude.com/claude-code)

## 📚 Documentation

- [Quick Start Guide](docs/QUICKSTART.md) - Get started in 5 minutes
- [API Reference](docs/API_REFERENCE.md) - Complete API documentation
- [Verification Report](docs/VERIFICATION.md) - Test results and metrics

## ✨ Features

- **Blazing Fast**: 5-6x faster than Ruby's CSV stdlib thanks to SIMD optimizations
- **Memory Efficient**: Streaming parser that doesn't load entire files into memory
- **API Compatible**: Familiar interface matching Ruby's CSV class
- **Native Extension**: Direct C integration for minimal overhead
- **Ruby 3.3+**: Modern Ruby support with proper encoding handling

## 📦 Installation

Add to your Gemfile:

```ruby
gem 'zsv'
```

Or install directly:

```bash
gem install zsv
```

The gem will automatically download and compile zsv 1.4.3 during installation.

## 🚀 Usage

### Basic Parsing

```ruby
require 'zsv'

# Parse entire file
rows = ZSV.read("data.csv")
# => [["a", "b", "c"], ["1", "2", "3"]]

# Stream rows (memory efficient)
ZSV.foreach("large_file.csv") do |row|
  puts row.inspect
end

# Parse string
rows = ZSV.parse("a,b,c\n1,2,3\n")
```

### Headers Mode

```ruby
# Use first row as headers
ZSV.foreach("data.csv", headers: true) do |row|
  puts row["name"]  # Hash access
end

# Provide custom headers
ZSV.foreach("data.csv", headers: ["id", "name", "email"]) do |row|
  puts row["name"]
end
```

### Parser Instance

```ruby
# Create parser
parser = ZSV.open("data.csv", headers: true)

# Read rows one at a time
row = parser.shift
row = parser.shift

# Iterate all rows
parser.each do |row|
  puts row
end

# Rewind to beginning
parser.rewind

# Clean up
parser.close

# Or use block form (auto-closes)
ZSV.open("data.csv") do |parser|
  parser.each { |row| puts row }
end
```

### Enumerable Methods

The parser includes `Enumerable`, so you can use `map`, `select`, `find`, etc.:

```ruby
# Transform rows
names = ZSV.open("users.csv", headers: true) do |parser|
  parser.map { |row| row["name"].upcase }
end

# Filter rows
adults = ZSV.open("users.csv", headers: true) do |parser|
  parser.select { |row| row["age"].to_i >= 18 }
end

# Find first match
admin = ZSV.open("users.csv", headers: true) do |parser|
  parser.find { |row| row["role"] == "admin" }
end
```

### Options

All parsing methods accept these options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `headers` | Boolean/Array | `false` | Use first row as headers or provide custom headers |
| `col_sep` | String | `","` | Column delimiter (single character) |
| `quote_char` | String | `"\""` | Quote character (single character) |
| `skip_lines` | Integer | `0` | Number of lines to skip at start |
| `encoding` | Encoding | `UTF-8` | Source encoding |
| `liberal_parsing` | Boolean | `false` | Handle malformed CSV gracefully |
| `buffer_size` | Integer | `262144` | Buffer size in bytes (256KB default) |

```ruby
# Tab-separated values
ZSV.foreach("data.tsv", col_sep: "\t") { |row| puts row }

# Pipe-separated values
ZSV.parse("a|b|c\n1|2|3", col_sep: "|")

# Skip header comment lines
ZSV.foreach("data.csv", skip_lines: 2) { |row| puts row }
```

## ⚡ Performance

Benchmarks comparing ZSV vs Ruby CSV stdlib (Ruby 3.4.7):

```
=== Small file (1K rows, 5 cols) ===
CSV (stdlib):   163.4 i/s
ZSV:          1,013.7 i/s - 6.20x faster

=== Medium file (10K rows, 10 cols) ===
CSV (stdlib):    10.3 i/s
ZSV:             54.5 i/s - 5.27x faster

=== Large file (100K rows, 10 cols) ===
CSV (stdlib):     1.1 i/s
ZSV:              5.3 i/s - 5.00x faster

=== With headers (10K rows) ===
CSV (stdlib):     7.8 i/s
ZSV:             33.8 i/s - 4.33x faster
```

### Memory Usage

ZSV uses significantly less memory than Ruby's CSV stdlib:

```
=== Memory Usage (100K rows) ===
CSV stdlib: 56.8 MB
ZSV:         9.9 MB - 82.6% less memory

=== String Allocations (10K rows) ===
CSV stdlib: 116,144 strings
ZSV:         50,005 strings - 56.9% fewer allocations
```

ZSV achieves **~6x lower memory usage** through frozen strings and efficient C-level memory management.

Run benchmarks yourself:

```bash
bundle exec rake bench
bundle exec ruby benchmark/memory_bench.rb
```

## API Reference

### Module Methods

#### `ZSV.foreach(path, **options) { |row| }`

Stream rows from a CSV file. Returns an Enumerator if no block given.

#### `ZSV.parse(string, **options) -> Array`

Parse CSV string and return all rows as an array.

#### `ZSV.read(path, **options) -> Array`

Read entire CSV file into an array.

#### `ZSV.open(path, mode="r", **options) -> Parser`

Open a CSV file and return a Parser instance. If a block is given, the parser is automatically closed after the block completes.

#### `ZSV.new(io, **options) -> Parser`

Create a Parser from any IO-like object.

### Parser Instance Methods

#### `#shift -> Array|Hash|nil`

Read and return the next row. Returns `nil` at EOF.

#### `#each { |row| } -> self`

Iterate over all rows. Returns Enumerator without block.

#### `#rewind -> nil`

Reset parser to the beginning (file-based parsers only).

#### `#close -> nil`

Close parser and release resources.

#### `#headers -> Array|nil`

Return headers if header mode is enabled.

#### `#closed? -> Boolean`

Check if parser is closed.

#### `#read -> Array`

Read all remaining rows into an array.

### Exception Classes

- `ZSV::Error` - Base exception class
- `ZSV::MalformedCSVError` - Raised on CSV parsing errors
- `ZSV::InvalidEncodingError` - Raised on encoding issues

## Architecture

The gem follows SOLID principles with clear separation of concerns:

```
ext/zsv/
├── zsv_ext.c     # Main extension entry point, Ruby API
├── parser.c/h    # Parser state management and zsv wrapper
├── row.c/h       # Row building and conversion (arrays/hashes)
├── options.c/h   # Option parsing and validation
└── common.h      # Shared types and macros
```

### Design Principles

1. **Single Responsibility**: Each C module handles one concern
2. **Streaming First**: Never load entire files into memory
3. **Zero-Copy Where Possible**: Minimize data copying
4. **Proper Resource Management**: RAII-style cleanup with Ruby GC

## 🛠️ Development

```bash
# Clone and setup
git clone https://github.com/sebyx07/zsv-ruby.git
cd zsv-ruby
bundle install

# Compile extension
bundle exec rake compile

# Run tests
bundle exec rake spec

# Run benchmarks
bundle exec rake bench

# Clean build artifacts
bundle exec rake clean
```

### Running Tests

```bash
bundle exec rspec
```

The test suite includes:

- Basic parsing tests
- Header mode tests
- Custom delimiter tests
- Error handling tests
- Memory leak detection
- API compatibility tests

## Compatibility

- **Ruby**: 3.3+ required (tested on 3.3, 3.4, 4.0)
- **Platforms**: Linux, macOS (ARM and x86)
- **ZSV**: Compiles against zsv 1.4.3

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure tests pass (`bundle exec rake spec`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

MIT License - see LICENSE file for details.

## 🙏 Credits

- Built on [zsv](https://github.com/liquidaty/zsv) by liquidaty
- Inspired by Ruby's CSV stdlib
- SIMD optimizations courtesy of zsv's excellent engineering
- Developed with [Claude Code](https://claude.com/claude-code)

## 🗺️ Roadmap

### Phase 1: Core Parser (Current)
- [x] Basic parsing (foreach, parse, read)
- [x] Header mode
- [x] Custom delimiters
- [x] File and string input

### Phase 2: CSV Stdlib Compatibility
- [ ] Type converters (`:numeric`, `:date`, `:date_time`)
- [ ] Header converters (`:downcase`, `:symbol`)
- [ ] `unconverted_fields` option

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/sebyx07/zsv-ruby/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sebyx07/zsv-ruby/discussions)
- **Upstream zsv**: [zsv repository](https://github.com/liquidaty/zsv)
