# zsv-ruby

A Ruby gem providing a SIMD-accelerated CSV parser that acts as a drop-in replacement for Ruby's CSV stdlib, roughly 5-6x faster. It is a native C extension wrapping the zsv 1.4.3 library; the gem version tracks the zsv version it compiles against. The core design problem it solves is bridging zsv's callback (push) parsing model to Ruby's pull-based CSV API (`shift`, `each`) via row buffering. It serves Ruby developers parsing large CSV files who want streaming, memory-efficient parsing without changing their code.

- **Stack:** Ruby 3.3+ (see `.ruby-version`, `mise.toml`), C extension built with rake-compiler; `ext/zsv/extconf.rb` downloads and builds zsv 1.4.3 at compile time into `ext/zsv/vendor/` (gitignored) and links `libzsv.a`. RSpec for tests, RuboCop for Ruby lint, clang-format (Linux kernel style) for C. Distributed as a gem; CI in `.github/`.
- **Key commands:** `bundle exec rake` (compile + spec, the default), `bundle exec rake compile`, `bundle exec rake spec`, `bundle exec rake clean`, `bundle exec rspec spec/zsv_spec.rb:194` (single test), `bundle exec rubocop` (0 offenses required), `bundle exec rake bench`.
- **Layout:**
  - `ext/zsv/` — the C extension: `zsv_ext.c` (Ruby bindings), `parser.c/h` (state + callback bridge, the critical file), `row.c/h` (cells → Array/Hash), `options.c/h`, `common.h`.
  - `lib/` — the Ruby-side gem code.
  - `spec/zsv_spec.rb` — all tests in one file.
  - `benchmark/` — `parse_bench.rb`, `memory_bench.rb`.
  - `examples/`, `docs/` — usage examples and QUICKSTART / API_REFERENCE / VERIFICATION docs.
- **Gotchas noted in CLAUDE.md:** never allocate Ruby objects during GC (check the `in_cleanup` flag in callbacks), call `zsv_finish()` exactly once (double call → double free → segfault), and `Parser.new` auto-detects CSV content vs a file path.
- **State as of 2026-07-21:** branch `main`, working tree was clean when this note was written.
