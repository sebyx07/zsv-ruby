# ZSV API Reference

ZSV reads CSV. Its API follows the reading half of Ruby's `CSV`; where it behaves differently, the difference is listed under [Differences from CSV](#differences-from-csv). Anything not listed here is not supported: an unknown option raises `ArgumentError`, it is never accepted and ignored.

- [Module methods](#module-methods)
- [ZSV::Parser](#zsvparser)
- [Options](#options)
- [Rows](#rows)
- [Malformed CSV](#malformed-csv)
- [Errors](#errors)
- [Differences from CSV](#differences-from-csv)

## Module methods

### ZSV.parse(string, **options) → Array

Parses CSV data held in a String and returns all rows. The argument is always data, never a path. Raises `TypeError` for anything but a String.

```ruby
ZSV.parse("a,b\n1,2\n")
# => [["a", "b"], ["1", "2"]]

ZSV.parse("name,age\nAlice,30\n", headers: true)
# => [{"name" => "Alice", "age" => "30"}]
```

### ZSV.parse_line(line, **options) → Array | Hash | nil

Returns the first row of the String, `nil` when it is empty. Like `CSV.parse_line`.

```ruby
ZSV.parse_line("a,b")  # => ["a", "b"]
ZSV.parse_line("")     # => nil
```

### ZSV.foreach(path, mode = "r", **options) { |row| } → nil

Streams the rows of a file, one at a time, in constant memory. `path` is a String or a Pathname. Without a block it returns an `Enumerator`.

```ruby
ZSV.foreach("data.csv") { |row| puts row.inspect }

ZSV.foreach("data.csv", headers: true) { |row| puts row["name"] }

# Enumerator: each_with_index, with_index, lazy, first...
ZSV.foreach("data.csv").with_index(1) { |row, line| puts "#{line}: #{row.first}" }
ZSV.foreach("data.csv", headers: true).lazy.select { |row| row["age"].to_i >= 18 }.first(10)
```

`mode` exists for call-site compatibility with `CSV.foreach`. Only read modes are accepted: `"r"`, `"rb"`, `"rt"`, each optionally followed by an encoding (`"r:bom|utf-8"`, `"r:ISO-8859-1"`), which is used as the `encoding` option. Any other mode raises `ArgumentError`.

### ZSV.read(path, **options) → Array

Reads a whole file into an Array of rows.

```ruby
rows = ZSV.read("data.csv")
rows = ZSV.read("data.csv", headers: true)
```

### ZSV.open(path, mode = "r", **options) → Parser

Opens a file and returns a [`ZSV::Parser`](#zsvparser). With a block, yields the parser, closes it when the block returns or raises, and returns the block's value. `mode` as in `ZSV.foreach`.

```ruby
parser = ZSV.open("data.csv", headers: true)
first = parser.shift
parser.close

count = ZSV.open("data.csv") { |parser| parser.count }
```

### ZSV.new(source, **options) → Parser

Same as `ZSV::Parser.new`.

### ZSV.parse_enum(source, **options) → Enumerator

An `Enumerator` over the rows of `source` (anything `ZSV::Parser.new` takes). Rows are parsed as they are consumed and the parser is closed when the enumeration ends.

```ruby
ZSV.parse_enum("a,b\n1,2\n3,4\n", headers: true).first
# => {"a" => "1", "b" => "2"}
```

## ZSV::Parser

Includes `Enumerable`: `map`, `select`, `find`, `each_with_index`, `lazy`, `first`, ... all work and consume the remaining rows.

### Parser.new(source, **options) → Parser

`source` is one of:

| Source | Treated as |
|---|---|
| IO-like object (responds to `#read` and `#eof?`: `File`, `StringIO`, sockets, ...) | A stream. Read in chunks as rows are consumed, from its current position. Fields are labelled with the IO's external encoding unless `encoding:` is given. |
| `Pathname` (responds to `#to_path`, is not a stream) | A file path. |
| String that is empty, or contains a line ending (`\n`, `\r`) or a NUL byte | CSV data. |
| Any other String naming an existing file | A file path. |
| Any other String containing `col_sep` | One line of CSV data. |
| Any other String | A file path, so a mistyped file name raises `Errno::ENOENT` rather than being parsed as data. |

Anything else raises `TypeError`. When the guess for Strings is not wanted, use `Parser.from_string` / `ZSV.parse` (always data) or `Parser.from_path` / `ZSV.open` (always a path).

```ruby
ZSV::Parser.new("a,b\n1,2\n")         # data
ZSV::Parser.new("data.csv")           # path
ZSV::Parser.new(Pathname("data.csv")) # path
ZSV::Parser.new($stdin)               # stream
```

### Parser.from_string(string, **options) → Parser

A parser over CSV data held in a String. Never treats it as a path.

### Parser.from_path(path, **options) → Parser

A parser over a file (String or Pathname). Never treats it as data. Raises `Errno::ENOENT` and friends.

### #shift → Array | Hash | nil

Returns the next row, `nil` at the end of the input and on a closed parser.

```ruby
parser = ZSV.open("data.csv")
first = parser.shift
second = parser.shift
```

### #each { |row| } → self

Yields the remaining rows. Without a block returns an `Enumerator`. `#each_row` is an alias.

```ruby
parser.each { |row| puts row.inspect }
parser.each.with_index { |row, index| ... }
```

### #read → Array

Returns the remaining rows. `#to_a` is an alias.

### #headers → Array | nil

The header names: the given ones with `headers: Array`/`String`; with `headers: true` the first row, available once a row has been read (`nil` before that); `nil` without headers.

```ruby
parser = ZSV.open("data.csv", headers: true)
parser.headers  # => nil
parser.shift
parser.headers  # => ["id", "name"]
```

### #rewind → nil

Starts over from the beginning of the input; with `headers: true` the header row is read again. Works for files and Strings, and for IOs that respond to `#rewind`. Raises `IOError` on a closed parser.

### #close → nil

Releases the parser and, for a path, its file. An IO given to `Parser.new` is not closed. Closing twice is fine.

### #closed? → Boolean

## Options

Every method above takes the same keyword options.

| Option | Values | Default | Meaning |
|---|---|---|---|
| `headers` | `false`/`nil`, `true`/`:first_row`, Array, String | `false` | `true`: the first row holds the header names and rows are Hashes. Array: these are the names, the first row is data. String: the names as one CSV line (split on `col_sep`). |
| `col_sep` | String of one ASCII character, not `"`, `\n` or `\r` | `","` | Field separator. |
| `quote_char` | `"\""` | `"\""` | Accepted only for call-site compatibility; zsv supports no other quote character. |
| `row_sep` | `:auto`, `"\n"`, `"\r\n"`, `"\r"` | `:auto` | Accepted only for call-site compatibility; `\n`, `\r\n` and `\r` are always all recognised, whichever value is given. |
| `skip_lines` | Integer ≥ 0 | `0` | Number of leading rows to drop, before the header row. |
| `liberal_parsing` | `true`, `false` | `true` | `false` raises on malformed CSV as `CSV` does. See [Malformed CSV](#malformed-csv). |
| `encoding` | `Encoding` or name, optionally as `"bom\|NAME"` or `"NAME:NAME"` | String: its encoding. IO: its external encoding. Path: UTF-8 | Encoding the returned Strings are labelled with. Bytes are never transcoded. Must be ASCII-compatible for paths and IOs. |
| `buffer_size` | Integer > 0 | `262144` | Size in bytes of the read buffer. Does not change the rows. |
| `max_row_size` | Integer > 0 | `262144` | Longest row, in bytes, that parses; a longer row raises `ZSV::MalformedCSVError`. |
| `max_columns` | Integer > 0 | `1024` | Most fields a row may have; a wider row raises `ZSV::MalformedCSVError`. |

Any other key raises `ArgumentError` (`unknown keyword: :converters`), as does a value outside the listed ones. That includes the `CSV` options ZSV does not implement: `converters`, `header_converters`, `unconverted_fields`, `return_headers`, `write_headers`, `skip_blanks`, `strip`, `nil_value`, `empty_value`, `field_size_limit`, `max_field_size`, `quote_empty`, `force_quotes`, `write_*`.

```ruby
ZSV.parse("a\tb\n1\t2\n", col_sep: "\t")
ZSV.foreach("export.csv", skip_lines: 2, headers: true) { |row| ... }
ZSV.parse("1,2\n3,4\n", headers: %w[id value])   # => [{"id" => "1", "value" => "2"}, ...]
ZSV.read("latin1.csv", encoding: "ISO-8859-1")
ZSV.read("excel.csv", encoding: "bom|utf-8")     # same as the default: a BOM is always dropped
```

### skip_lines

`skip_lines: 2` drops the first two rows. A row is what the parser reads as one record, so a quoted field containing line breaks counts once. `CSV` takes a Regexp or String here and drops the matching lines anywhere in the input; ZSV rejects those with `ArgumentError`.

### encoding

ZSV parses bytes and labels the resulting Strings; it does not transcode. `"ISO-8859-1:UTF-8"` (transcoding in `CSV`) raises `ArgumentError`; `"UTF-8:UTF-8"` and `"UTF-8:-"` are accepted. A String in an encoding that is not ASCII-compatible (UTF-16, UTF-32) is converted to UTF-8 before parsing and yields UTF-8 fields; for paths and IOs such an encoding raises `ArgumentError`.

In the default lenient mode bytes are not checked against the encoding: a field can come back with `valid_encoding? == false`. With `liberal_parsing: false` invalid bytes raise `ZSV::InvalidEncodingError`.

### max_row_size, buffer_size

A row of up to `max_row_size` bytes always parses completely, whatever `buffer_size` is: the parser's buffer is at least `buffer_size` and at least `max_row_size + 1` bytes, allocated when the parser is created. The size counts the row's raw bytes (quotes and escaped quotes included) without its line ending; a quoted field spanning several lines is part of one row.

A longer row raises `ZSV::MalformedCSVError` ("Row longer than max_row_size (262144 bytes) in line 2.", `#line_number` the 1-based record) instead of being returned cut short. Rows already returned stay valid. For data with longer rows, set `max_row_size` above the longest one; the buffer grows with it.

`max_columns` works the same way: a wider row raises ("Row with more than max_columns (1024) fields in line 1.") rather than losing its last fields.

## Rows

- Without headers a row is an `Array` of Strings; with headers it is a `Hash` with the header names as String keys, in header order.
- All field and key Strings are frozen. The Arrays and Hashes are not.
- An empty field is `""`, quoted or not. A blank line is `[]` (with headers: every key mapped to `nil`).
- With headers, a row shorter than the header row has `nil` for the missing fields. A row longer than the header row keeps the extra fields under their Integer column index (`{"a" => "1", "b" => "2", 2 => "3"}`).
- When a header name repeats, its first column wins, as in `CSV::Row#to_h`.
- A UTF-8 byte order mark at the start of the input is dropped.

## Malformed CSV

By default ZSV is lenient: it never raises for quoting problems and returns what the zsv parser makes of the input.

| Input | `ZSV.parse(input)` | `CSV.parse(input)` |
|---|---|---|
| `a,b"c,d` (quote inside an unquoted field) | `[["a", "b\"c", "d"]]` | `Illegal quoting in line 1.` |
| `a, "b",c` (space before the opening quote) | `[["a", " \"b\"", "c"]]` | `Illegal quoting in line 1.` |
| `a,"b"c,d` (text after the closing quote) | `[["a", "bc", "d"]]` | `Any value after quoted field isn't allowed in line 1.` |
| `a,"b` + more lines (quote never closed) | the field runs to the end of the input | `Unclosed quoted field in line 1.` |

The first two rows equal `CSV`'s `liberal_parsing: true`; the third does not (`CSV` returns `"\"b\"c"`).

### liberal_parsing: false

Makes ZSV reject what `CSV` rejects, with the same message and line number:

```ruby
ZSV.parse(%(a,b\n1,x"y\n), liberal_parsing: false)
# ZSV::MalformedCSVError: Illegal quoting in line 2.

begin
  ZSV.foreach("data.csv", liberal_parsing: false) { |row| ... }
rescue ZSV::MalformedCSVError => e
  e.line_number  # => 2
end
```

- Detected: `Illegal quoting`, `Any value after quoted field isn't allowed`, `Unclosed quoted field` (`ZSV::MalformedCSVError`), and bytes invalid in the encoding (`ZSV::InvalidEncodingError`, `Invalid byte sequence in UTF-8 in line N.`).
- The line number counts records as `CSV` does: a quoted field spanning several lines counts once. Records are told apart by `\n`, so for input using a lone `\r` as line ending the number is always 1.
- The check is a separate pass over the whole input before parsing starts. The error is therefore raised by the call itself (`ZSV.foreach`, `ZSV.open`, `Parser.new`), before any row is yielded, where `CSV` raises when it reaches the bad row. A file is read twice; an IO is read to its end into memory.
- It costs time: little for data without quotes, more for data full of quoted fields. `benchmark/parse_bench.rb` measures it.
- The whole input is checked, including rows dropped by `skip_lines`.

## Errors

| Class | Raised when |
|---|---|
| `ZSV::Error` < `StandardError` | Base class; also raised when a parser is used from inside its own callbacks. |
| `ZSV::MalformedCSVError` < `ZSV::Error` | Malformed CSV with `liberal_parsing: false`; a row longer than `max_row_size` bytes or with more than `max_columns` fields. |
| `ZSV::InvalidEncodingError` < `ZSV::Error` | Bytes invalid in the encoding, with `liberal_parsing: false`. |
| `ArgumentError` | Unknown option, unsupported option value, non-read mode. |
| `TypeError` | A source of the wrong type. |
| `Errno::ENOENT`, `Errno::EACCES`, ... | The file cannot be opened. |
| `IOError` | `#rewind` on a closed parser. |

`MalformedCSVError` and `InvalidEncodingError` have `#line_number` (alias `#lineno`) like their `CSV` counterparts; it is `nil` for errors not tied to a line. They are not subclasses of the `CSV` errors: rescue `ZSV::MalformedCSVError`.

## Differences from CSV

ZSV matches `CSV` for the inputs and options in `spec/api/csv_compat_spec.rb`, except for the following.

| | `CSV` | ZSV |
|---|---|---|
| Empty unquoted field (`a,,b`) | `nil` | `""`, as with `CSV`'s `nil_value: ""` |
| Row and table classes | `CSV::Row`, `CSV::Table` | `Hash`, `Array` |
| Strings | mutable | frozen |
| Fields beyond the header row | all under the key `nil` | under their Integer column index |
| UTF-8 BOM | kept unless `encoding: "bom\|utf-8"` | always dropped |
| Malformed quoting | raises unless `liberal_parsing: true` | lenient unless `liberal_parsing: false` |
| When a malformed row raises | on reaching the row | before the first row |
| Mixed line endings in one input | uses the first kind, rejects the others | each `\n`, `\r\n`, `\r` ends a row |
| `col_sep` | any String | one ASCII character |
| `quote_char` | any character, or `nil` | `"` only |
| `row_sep` | any String | `\n`, `\r\n`, `\r`, auto-detected |
| `skip_lines` | Regexp or String matcher | number of leading rows |
| `encoding: "A:B"` | transcodes | rejected unless nothing is transcoded |
| Row limits | none | `max_row_size`, `max_columns` |
| `#headers` before the first read | `true` | `nil` |
| `#shift` / `#each` on a closed parser | `IOError` | `nil` / no rows |
| Converters, `strip`, `skip_blanks`, `nil_value`, ... | supported | `ArgumentError` |
| Writing (`CSV.generate`, `<<`, modes `"w"`, `"a"`) | supported | not supported |
