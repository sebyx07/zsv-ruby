# ZSV-Ruby Quick Start

## Installation

```bash
# Clone the repository
git clone https://github.com/your-org/zsv-ruby.git
cd zsv-ruby

# Install dependencies
bundle install

# Compile the extension (downloads zsv 1.4.3 automatically)
bundle exec rake compile

# Run tests
bundle exec rake spec
```

## Build from Scratch

The gem will automatically:
1. Download zsv 1.4.3 source from GitHub
2. Configure and compile zsv library
3. Build the Ruby extension
4. Link everything together

No manual installation of zsv required!

## Usage

```ruby
require 'zsv'

# Parse a CSV file (memory efficient, streaming)
ZSV.foreach("data.csv") do |row|
  puts row.inspect
end

# With headers
ZSV.foreach("data.csv", headers: true) do |row|
  puts "Name: #{row['name']}, Age: #{row['age']}"
end

# Parse a string
rows = ZSV.parse("a,b,c\n1,2,3\n")
# => [["a", "b", "c"], ["1", "2", "3"]]

# Custom delimiter
ZSV.parse("a|b|c\n1|2|3\n", col_sep: "|")

# Parser instance
parser = ZSV.open("data.csv", headers: true)
row1 = parser.shift
row2 = parser.shift
parser.close
```

## Running Tests

```bash
# All tests
bundle exec rake spec

# Specific test
bundle exec rspec spec/zsv_spec.rb:10

# With coverage
bundle exec rspec --format documentation
```

## Running Benchmarks

```bash
bundle exec rake bench
```

## Development

```bash
# Clean build artifacts
bundle exec rake clean

# Rebuild
bundle exec rake compile

# Run examples
ruby examples/basic_usage.rb
```

## Troubleshooting

### Compilation fails
- Ensure Ruby 3.3+ is installed
- Check that curl and tar are available
- Try `bundle exec rake clean && bundle exec rake compile`

### Tests fail
- Recompile: `bundle exec rake clean compile spec`
- Check Ruby version: `ruby --version`

### Performance not improved
- Verify SIMD is enabled: check compilation output for AVX2/SSE2
- Ensure -O3 optimization is active
- Run benchmarks to measure

## Quick Test

```bash
ruby -rzs v -e 'puts ZSV.parse("a,b\n1,2").inspect'
# => [["a", "b"], ["1", "2"]]
```
