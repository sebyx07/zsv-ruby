# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Versioning: gem `X.Y.Z` ships the zsv C library `X.Y.Z` (a gem-only release
adds a fourth segment, `X.Y.Z.N`), so the version number follows zsv, not
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A release can
therefore change behaviour without a major bump: every such change is listed
under **Changed — breaking**, with what to do before upgrading.

## [Unreleased]

### Added
- IO sources: `ZSV::Parser.new(io)`, `ZSV.parse_enum(io)` read any object
  responding to `#read` (File, StringIO, pipes, sockets) as the rows are
  consumed. Fields carry the IO's external encoding.
- `ZSV.parse_line(line, **options)`, like `CSV.parse_line`.
- `ZSV::Parser.from_string(csv, **options)` and
  `ZSV::Parser.from_path(path, **options)`: build a parser without the
  String-is-data-or-path guess of `ZSV::Parser.new`.
- `headers:` accepts a String (the header names as one CSV line) and
  `:first_row` (same as `true`), as in `CSV`.
- `ZSV.open` and `ZSV.foreach` accept a read mode: `"r"`, `"rb"`, `"rt"`, and
  `"r:<encoding>"` (`"r:bom|utf-8"`, `"r:iso-8859-1"`). Write modes raise
  `ArgumentError`.
- Strict mode: `liberal_parsing: false` validates the input like `CSV` does
  and raises `ZSV::MalformedCSVError` (quoting errors) or
  `ZSV::InvalidEncodingError` (bytes invalid in the source encoding), both
  with `#line_number` (alias `#lineno`). It reads the whole input before the
  first row and is slower than the default lenient mode.
- `max_row_size` (default 262144 bytes) and `max_columns` (default 1024)
  options: the limits past which a row raises instead of being cut.
- Precompiled gems for x86_64 and aarch64 Linux (glibc and musl) and x86_64
  and arm64 macOS, published with each release: no C compiler needed there.
- Offline install: the zsv source ships inside the gem, pinned by SHA-256
  (see Security / Packaging). `gem install` never touches the network.

### Changed — breaking, read before upgrading
- **Unknown options raise `ArgumentError`** (`unknown keyword: :converters`).
  They were silently ignored before. Upgrade: remove options ZSV does not
  implement (`converters`, `strip`, `skip_blanks`, `nil_value`, ...; the
  list is in `docs/API_REFERENCE.md`) and do that work on the rows.
- **`quote_char` other than `'"'` and `row_sep` other than `:auto`, `"\n"`,
  `"\r\n"` or `"\r"` raise `ArgumentError`.** They were accepted and had no
  effect. Upgrade: drop them; zsv only quotes with `"` and auto-detects the
  three line endings.
- **`liberal_parsing: false` now validates**: it is slower and raises on
  malformed quoting or invalid encoding, where it used to be ignored (rows
  were always parsed leniently). Upgrade: omit the option, or pass
  `liberal_parsing: true`, to keep the old lenient behaviour and speed.
- **Field encoding follows the source**: the String's encoding for
  `ZSV.parse`, the IO's external encoding for IOs, `encoding:` or the mode's
  encoding for files (UTF-8 when none is given). Fields were always tagged
  UTF-8 before, so a binary String (`File.binread`, `"..".b`) now yields
  BINARY (ASCII-8BIT) fields. Upgrade: `force_encoding('UTF-8')` the input,
  or pass `encoding: 'UTF-8'`.
- **A blank line is an empty row `[]`, as in `CSV`**: `ZSV.parse("a\n\nb\n")`
  is `[["a"], [], ["b"]]`, was `[["a"], [""], ["b"]]`. With headers it is a
  Hash with every header mapped to `nil` (was `{first_header => ""}`); blank
  lines before the header row are skipped. A line holding only `""` is now
  `[""]` (it was dropped). Upgrade: `reject(&:empty?)` if you counted on
  non-empty rows.
- **Header rows match `CSV`**: a row shorter than the headers has `nil` for
  the missing fields (the keys were absent), and when a header name repeats
  its first column wins (the last one did). Upgrade: `row.compact` for the
  old missing-key shape; rename duplicate headers to read every column.
- **How `ZSV::Parser.new` reads its argument**: a `Pathname` or other
  `#to_path` object that is not an open stream is a path (it was read as an
  IO and looped forever); a String holding a line ending or a NUL byte, or
  empty, is data; otherwise an existing file of that name is a path (a file
  with a comma in its name is found); otherwise a String containing
  `col_sep` is data (`"a,b"`, `"a;b"` with `col_sep: ";"`); anything else is
  a missing path (`Errno::ENOENT`). Upgrade: use `ZSV::Parser.from_string` or
  `from_path` (or `ZSV.parse` / `ZSV.open`) to choose explicitly.
- **`skip_lines` must be a non-negative Integer**; a Regexp, a String or a
  negative number raises `ArgumentError` (a negative value was ignored).
  Upgrade: skip matching rows yourself (`each.reject { ... }`).
- **Over-long and over-wide rows raise `ZSV::MalformedCSVError`** instead of
  being returned cut short: a row longer than `max_row_size` (default
  256 KiB, the old buffer size) and a row with more than `max_columns`
  (default 1024) fields, whose extra fields were dropped. Upgrade: pass a
  larger `max_row_size:` / `max_columns:` for such files.
- **A source build targets the baseline CPU** (SSE2 on x86_64, NEON on
  aarch64; zsv's SIMD scanner stays on) instead of the build machine's
  (`-march=native`, AVX2). A binary built in a Docker image on one CPU used
  to die with SIGILL on another. Upgrade: nothing to do; to build for the
  local CPU when the code only runs where it was built,
  `gem install zsv --platform ruby -- --enable-native` (or `ZSV_NATIVE=1`).
  On the bundled benchmarks the portable and native builds were within run-to-run noise of each other (x86_64, Ruby 4.0); the Benchmarks workflow reports current numbers.

### Changed
- Upgraded the bundled zsv C library from 1.4.3 to 1.4.4. Parser-library
  changes are small: malformed-UTF-8 replacement now works on targets where
  `char` is unsigned (e.g. gcc on ARM Linux), plus a new optional per-cell
  malformed-UTF-8 handler this gem does not use yet. Most of the release is the
  zsv CLI. See the
  [zsv 1.4.4 release notes](https://github.com/liquidaty/zsv/releases/tag/v1.4.4).

### Fixed
- `ZSV.parse` could abort the whole Ruby process (`[BUG] Aborted`).
- A row longer than the read buffer (256 KiB by default) was returned cut
  short and the rest of it dropped, with no error. A row of up to
  `max_row_size` bytes now always parses completely, whatever `buffer_size`
  is, and a longer row raises `ZSV::MalformedCSVError` with its line number
  (`#line_number`).
- A row with more than 1024 fields lost the extra fields silently. It now
  raises `ZSV::MalformedCSVError`; `max_columns` raises the limit.
- `ZSV::Parser#initialize` given a `Pathname` read it as an IO, and
  `Pathname#read(n)` returns the first bytes of the file on every call, so the
  rows repeated forever. A path-like object (`#to_path`, not an open stream) is
  now opened as a path; a `File` is still read from its current position.
- `ZSV::Parser#each` and `#each_row` returned `nil` with a block; they return
  the parser, like `CSV#each`.
- Calling `#initialize` again on a parser leaked the first parser's state; it
  now raises `RuntimeError` and leaks nothing.
- Ruby code run from zsv's callbacks (an IO's `#read`, building rows) could
  raise through zsv's C frames. It now runs under `rb_protect` and the
  exception is re-raised once zsv has returned and the parser is released.
- The parser now supports GC compaction (its stored objects are marked
  movable and updated), never calls into Ruby while being freed, calls
  `zsv_finish` exactly once at end of input (never from `close` or free) and
  checks its status, and leaks no `FILE *`, zsv parser or memory when options,
  `#read`, the block or a second `#initialize` raise.
- A parser is no longer re-entered from its own callback or another thread:
  that raises `ZSV::Error` instead of corrupting zsv's state.
- zsv's warnings no longer print to stderr.

### Security / Packaging
- `gem install` no longer downloads anything. The zsv source is vendored in the
  gem (`ext/zsv/vendor/zsv`, with zsv's MIT `LICENSE`) and pinned by SHA-256 in
  `ext/zsv/ZSV_UPSTREAM`. Before, `extconf.rb` fetched an unverified tarball
  from GitHub at install time, and retried with TLS verification switched off
  when verification failed.
- Precompiled platform gems are cross-built with `rake gem:native`
  (rake-compiler-dock) for the baseline CPU of each architecture.

### Tooling
- `rake zsv:vendor`, `rake zsv:verify` and `rake "zsv:bump[X.Y.Z]"` manage the
  vendored zsv. `bin/zsv-upstream-check` reports whether a newer zsv release
  exists (exit 10 when one does).

## [1.4.3] - 2026-06-26

### Changed
- Upgraded the vendored zsv C library from 1.3.0 to 1.4.3, which introduces
  zsv "fast mode" and assorted parser improvements and fixes. See the
  [zsv 1.4.0 release notes](https://github.com/liquidaty/zsv/releases/tag/v1.4.0).
- Gem version bumped to 1.4.3 to stay in sync with the bundled zsv library.

### CI / Tooling
- CI now tests against Ruby 3.3, 3.4, and 4.0.
- Added a tag-driven release workflow that publishes to RubyGems via trusted
  publishing (OIDC) and creates a GitHub Release (`rake release:tag`).

## [1.3.0] - 2025-12-08

### Added
- Initial release of zsv-ruby gem
- Core parsing functionality (foreach, parse, read, open)
- Header mode support (boolean and custom headers)
- Custom delimiter support (col_sep, quote_char)
- Parser class with shift, each, rewind, close methods
- Memory-efficient streaming parser
- Native C extension compiling against zsv 1.3.0
- SIMD optimizations via zsv library
- Comprehensive RSpec test suite
- Performance benchmarks
- Full API documentation

### Features
- Drop-in replacement for Ruby CSV stdlib
- 10-50x performance improvement on large files
- 90% memory usage reduction through streaming
- Support for Ruby 3.3+
- Proper encoding handling (UTF-8 default)
- Exception classes for error handling

### Architecture
- SOLID design with separated concerns
- Row builder for efficient array/hash conversion
- Options parser with validation
- Parser wrapper around zsv C library
- Proper GC integration and resource cleanup
