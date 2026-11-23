# Data model

A parser library has no database. Its "data" is the public API users write against, the rows it
returns, and the state the C extension keeps while parsing.

## Public API

- **Entry points:** module methods on `ZSV` (`foreach`, `parse`, `parse_line`, `read`, `open`,
  `new`, `parse_enum`) and `ZSV::Parser` (`new`, `from_string`, `from_path`, `shift`, `each`,
  `read`, `headers`, `rewind`, `close`, `closed?`). Defined in `lib/zsv.rb` over the C methods.
- **Sources:** a path, a String of CSV data, or any object responding to `#read`
  (`lib/zsv/input.rb` resolves which).
- **Options:** one keyword set shared by every entry point, normalised and validated in
  `lib/zsv/options.rb` and range-checked again in `ext/zsv/options.c`. An unknown key or value
  raises `ArgumentError`.
- **Rows:** an `Array` of frozen Strings, or with headers a `Hash` keyed by the header names.
- **Errors:** `ZSV::Error`, `ZSV::MalformedCSVError`, `ZSV::InvalidEncodingError`
  (`lib/zsv/errors.rb`).

The full, current list of methods, options and differences from `CSV` is
`docs/API_REFERENCE.md`; `llms.txt` is the same reference for AI tools.

## State in C

- `zsv_ruby_parser_t` (`ext/zsv/parser.h`): one per `ZSV::Parser`. It owns the zsv parser, the
  `FILE *` for a path source, the source object for a String or IO, the buffer of rows zsv has
  pushed and Ruby has not pulled yet, and the recorded exception state.
- `zsv_row_builder_t` (`ext/zsv/row.h`): turns one row's cells into a Ruby row; holds the headers.
- `zsv_ruby_options_t` (`ext/zsv/options.h`): the options as C values.

Every Ruby object these structs hold is marked and updated on compaction: `ext/CLAUDE.md` § Rules.

## The pin

`ext/zsv/ZSV_UPSTREAM` holds two lines, `version=` and `sha256=`: the zsv release this gem is built
from and the hash of its upstream tarball. `lib/zsv/version.rb` mirrors that version
(`bin/repo-guards` checks it).
