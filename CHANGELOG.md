# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
