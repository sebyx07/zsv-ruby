# Hygiene checkup

Weekly checkup, Sundays 17:00 UTC, OFFERED and off: the `hygiene` entry in
`.dz/maintainer/maintainer.yml` is commented out, and uncommenting it is the opt-in. It is the
developerz.ai platform's standard hygiene checkup, adapted to a Ruby gem that is a C extension over
a vendored C library: a deep read for the defects tests never show. A read-only scout: you read
files only, no shell, network or database, so a finding whose harm you cannot prove from the code
(a leak's size, a hot path's cost, whether a sanitizer would fire) is marked `measure first: yes`,
never guessed. Read `CLAUDE.md` and `ext/CLAUDE.md` first: their invariants and numbered rules
define what a defect is here, and the monthly `improve` task (`.dz/schedules/improve.md`) already
runs the sanitizers and the benchmarks, so do not file what its open pull request covers.

## What to look for

1. **Resource lifetimes and GC safety.** This code runs inside the user's process, so each of these
   is a crash or a leak in their application:
   - a `VALUE` stored in `zsv_ruby_parser_t`, `zsv_row_builder_t` or `zsv_ruby_options_t` with no
     line in `zsv_parser_mark` (or `zsv_row_builder_mark`) or none in `zsv_parser_compact`;
   - a raw pointer (`RSTRING_PTR`, `RARRAY_CONST_PTR`, bytes from `zsv_get_cell`) used after a call
     that can allocate, compact, run Ruby code or advance the parser, or with no `RB_GC_GUARD`;
   - a `FILE *`, a zsv parser or an `xmalloc`'d buffer not released on some exit path: a raise from
     options, from an IO's `#read`, from the block, a `break`, a second `close`, a second
     `#initialize`, a parser dropped unclosed;
   - Ruby reached from the free path (allocation, `rb_raise`, `rb_funcall` under `dfree`);
   - `zsv_finish()` reachable twice or from close, free or rewind; `zsv_delete()` or `fclose()`
     reachable twice;
   - a module method in `lib/zsv.rb` that opens a parser and does not close it in `ensure`.
2. **Algorithms.** Work repeated per row or per cell on the hot path (`ext/zsv/row.c`, the row
   handler in `ext/zsv/parser.c`): an encoding lookup, a header String or a Hash key rebuilt for
   every row, a Ruby method call where a C API call exists, a whole input read into memory where it
   was streamed. In `lib/`: a Regexp or an options Hash rebuilt per row.
3. **Reuse.** A hand-rolled copy of a helper the repository already has: the error macros and
   `ZSV_ALLOC*` in `ext/zsv/common.h`, option validation in `lib/zsv/options.rb` against
   `ext/zsv/options.c`, input resolution in `lib/zsv/input.rb`, `with_csv_file` and `csv_rows` in
   `spec/`. Name both the copy and the original.
4. **Data.** There is no database, migration or schema file here. This area is clean unless one
   appears; say so in one line.
5. **Documentation drift.** In `README.md`, `CLAUDE.md` and the nested ones, `llms.txt`,
   `docs/`, `CONTRIBUTING.md` and `RELEASE.md`: a path that no longer exists, a command naming a
   script or rake task the repository does not define, an option, method or error class the code
   no longer has, an option listed as compatible with `CSV` that `lib/zsv/options.rb` rejects, a
   hardcoded Ruby or OS version list, a speed or memory figure with no benchmark run behind it.
   Quote both the doc line and the code.
6. **Code quality.** An ignored `enum zsv_status`; a `size_t` / `long` / `int` narrowing with no
   range check; growth arithmetic with no overflow check; a blanket `rescue` that returns `nil` or
   `[]`; an option accepted and ignored; dead code (a static function nothing calls, a struct field
   nothing reads, an option nothing uses); a function far beyond its file's norm.
7. **Infrastructure.** The build and the package: a host-specific compiler flag on the default path
   of `ext/zsv/extconf.rb` (`-march=native` outside `--enable-native`), a disabled warning, anything
   that downloads or links a system libzsv, a file the gem needs that `spec.files` in `zsv.gemspec`
   does not ship, a runtime dependency in the gemspec, a `NATIVE_PLATFORMS` entry in the `Rakefile`
   that nothing smoke-tests. Skip CI configuration (workflow files), `.dz/` and secret-shaped
   paths: a handoff naming one is refused whole.

## Rows

One per area above; a handoff reports one failing row.

- `leak`: resource lifetimes
- `algo`: algorithms
- `reuse`: reuse
- `index`: data
- `doc-drift`: documentation drift
- `quality`: code quality
- `infra`: infrastructure

## How to judge

- Confirm before you claim: read the call path, through the callback → pull bridge when it crosses
  it. A pattern is a finding only once you have seen that it runs where it hurts.
- Rank by blast radius: what crashes or corrupts the user's process first (`leak`), then silent
  data loss, then docs naming something that does not exist, quality last.
- Skip `spec/`, `benchmark/`, `examples/` and generated files. Never file a change under
  `ext/zsv/vendor/`: it is upstream's code, pinned by hash; a zsv bug is reported upstream.
- One handoff per row: every defect in an area goes in it, worst first.
- A fix that changes the rows returned for an input, an option's default or the public API is
  breaking: report it for the owner, do not file it.

## Every finding

Besides the checkup rules' fields, each handoff carries these; one over any limit is dropped whole:

- **work**: one sentence naming the defect and the fix, at most 300 characters.
- **why**: a concrete failure scenario, what triggers it and what breaks, at most 300 characters.
- **evidence**: at most 10 lines of at most 280 characters each. Up to 8 lines `path:line: the
  code`, one per site; with more sites, a 9th line "and N more sites like it in <directories>".
  The last line starts `measure first:`. Write `measure first: no` with the reason when the code
  alone proves the harm, or `measure first: yes` with what to measure and how: a spec under
  `GC.stress = true` and `GC.verify_compaction_references`, then `bin/check asan`, for a lifetime
  finding; `bundle exec rake bench` before and after for a cost. The coding agent that takes the
  handoff measures first, and drops the fix if nothing fails or moves.
- **paths**: at most 20 files.
- **anchor**: the row id (`leak:`, `algo:`, `reuse:`, `index:`, `doc-drift:`, `quality:` or
  `infra:`), then the worst file or symbol, at most 120 characters.
- **metric**: the number the fix moves, at most 200 characters.

## Report

For each of the seven areas: what you read and whether it was clean. Name any area you could not
cover, and why.
