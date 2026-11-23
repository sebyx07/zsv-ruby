# Stack

- **Languages:** Ruby (`lib/`, the public API) and C99 (`ext/zsv/*.c`, the extension), over the
  vendored zsv C library (`ext/zsv/vendor/zsv/`, pinned in `ext/zsv/ZSV_UPSTREAM`).
- **Build:** mkmf (`ext/zsv/extconf.rb`) builds the vendored zsv with its own `./configure` and
  `make`, and links it statically; rake-compiler drives it (`rake compile`). Precompiled platform
  gems are cross-built with rake-compiler-dock for the `NATIVE_PLATFORMS` in the `Rakefile`.
- **Tests:** RSpec (`spec/`) against the compiled extension, with parity specs that compare with
  Ruby's `CSV`; the same suite under AddressSanitizer and UBSan (`bin/check asan`).
- **Lint and format:** RuboCop (`.rubocop.yml`) for Ruby, clang-format (`.clang-format`) for our C.
- **Benchmarks:** benchmark-ips scripts in `benchmark/`, run by `rake bench`.
- **Toolchain:** the Ruby in `.ruby-version` (installed by mise through `mise.toml`, or rbenv), a C
  compiler and `make`. The Ruby floor is `required_ruby_version` in `zsv.gemspec`; tested Rubies
  and platforms are the matrix in `.github/workflows/ci.yml`.
- **Gate:** `bin/check` locally and the `CI OK` job in `.github/workflows/ci.yml`, which runs the
  same `bin/check` plus the Ruby x OS matrix, the sanitizers, the package build and workflow lint.
- **Runtime dependencies:** none, by rule (`zsv.gemspec`).

Development gem versions are in `zsv.gemspec` and the `Gemfile`; Dependabot keeps them current.
The zsv library is followed by the monthly `upstream-zsv` task (`.dz/schedules/upstream-zsv.md`).
