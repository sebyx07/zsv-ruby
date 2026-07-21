# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

zsv-ruby: SIMD-accelerated CSV parser gem that's 5-6x faster than Ruby's CSV stdlib. Native C extension wrapping zsv 1.4.3 library. Compiles against zsv 1.4.3, version numbers stay in sync.

## Essential Commands

```bash
# Build & Test (most common workflow)
bundle exec rake              # Default: compile + spec
bundle exec rake compile      # Build C extension
bundle exec rake spec         # Run tests (28 examples)
bundle exec rspec spec/zsv_spec.rb:194  # Run single test

# Code Quality
bundle exec rubocop                      # Lint Ruby (single quotes, nested modules)
bundle exec rubocop --auto-correct-all   # Auto-fix

# Clean Build
bundle exec rake clean        # Remove artifacts
bundle exec rake clean compile spec  # Full rebuild + test

# Benchmarks
bundle exec rake bench        # Run all benchmarks
```

## Architecture (Callback → Pull Bridge)

**Core Challenge**: zsv uses callback-based parsing (push model), but Ruby's CSV API is pull-based (`shift()`, `each`). We bridge this with row buffering.

### C Extension Structure (~1000 LOC)

```
ext/zsv/
├── zsv_ext.c        # Ruby API bindings, Init_zsv(), module methods
├── parser.c/h       # Parser state + callback bridge (THE CRITICAL FILE)
├── row.c/h          # Row builder (zsv cells → Ruby Array/Hash)
├── options.c/h      # Hash options → C struct conversion
└── common.h         # Shared macros, module refs
```

### Key Architecture Points

**parser.c** - The Complex Part:
- `zsv_row_handler()`: Callback from zsv (called per row during parse)
  - Builds row from zsv cells
  - Pushes to `parser->row_buffer` (Ruby array)
  - Handles header detection (first row or custom)

- `zsv_parser_shift()`: Pull interface
  - Returns buffered row if available
  - Calls `zsv_parse_more()` which triggers callbacks
  - Calls `zsv_parser_finish_safe()` at EOF to flush final row (handles no-trailing-newline)

- **GC Safety**: `parser->in_cleanup` flag prevents Ruby object allocation during zsv_finish/delete (GC phase)

**row.c** - Row Building:
- Accumulates cells in dynamic array
- Converts to Ruby Array or Hash (depending on headers)
- Uses `rb_enc_str_new()` + `rb_str_freeze()` for memory efficiency

**options.c** - Option Parsing:
- Converts Ruby hash `{headers: true, col_sep: '|'}` to C struct
- Distinguishes `headers: true` (read from file) vs `headers: ['a','b']` (custom)

### Critical Invariants

1. **Never allocate Ruby objects during GC**: Check `parser->in_cleanup` before `rb_*` calls in callbacks
2. **zsv_finish() called exactly once**: Either in `shift()` at EOF or in `close()`, tracked by `parser->eof_reached`
3. **Custom headers skip first row**: When `header_array != Qnil`, set `header_row_processed = true` immediately
4. **String vs file path detection**: In `Parser.new()`, check for '\n' or ',' to distinguish CSV content from filepath

## Build System

**extconf.rb downloads zsv at compile time**:
1. Downloads zsv 1.4.3 tarball using Ruby Net::HTTP (no system curl)
2. Extracts to `ext/zsv/vendor/` (gitignored)
3. Runs `./configure && make -C src build`
4. Links against `build/Linux/rel/gcc/lib/libzsv.a`
5. Flags: `-O3` for performance, `-I vendor/zsv-1.4.3/include`

## Testing Strategy

**RSpec (28 examples)**:
- Use `with_csv_file()` helper for file-based tests
- Parser.new() accepts strings OR file paths (auto-detects)
- Headers mode: test both `headers: true` and `headers: ['custom']`
- Edge case: CSV without trailing newline (zsv_finish handles this)

**Run specific test by line**: `bundle exec rspec spec/zsv_spec.rb:106`

## Common Pitfalls

1. **Don't call zsv_finish() twice**: Causes double-free → segfault
2. **Don't allocate in GC phase**: Check `in_cleanup` flag in all callbacks
3. **Initialize DATA_PTR properly**: Use `zsv_parser_alloc()` allocfunc, NOT wrap_parser
4. **Handle EOF correctly**: Call zsv_finish() before marking `eof_reached = true`

## Style Guide

- Ruby: Single quotes, frozen string literals, nested modules
- C: Linux kernel style (via .clang-format)
- Use SOLID principles, avoid over-abstraction
- RuboCop: 0 offenses required

## File Locations

- Docs: `docs/` (QUICKSTART, API_REFERENCE, VERIFICATION)
- Tests: `spec/zsv_spec.rb` (one file, all tests)
- Examples: `examples/basic_usage.rb`, `examples/performance_comparison.rb`
- Benchmarks: `benchmark/parse_bench.rb`, `benchmark/memory_bench.rb`

## Note

Do not use git worktrees — work directly in this checkout. If a task is big enough to need subagents, run them as a team in this same checkout: split the work into disjoint pieces so no two agents touch the same files.
