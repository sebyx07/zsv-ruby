# Reviewer instructions — sebyx07/zsv-ruby

> Read by the developerz.ai reviewer at EVERY review of this repository, at the reviewed
> commit, as this repo's own layer of the reviewer's prompt. It refines the platform rules
> (a finding is cited or withheld; the bot always discloses) and never overrides them.
> `CLAUDE.md` and `ext/CLAUDE.md` are the source of truth; this file is their review-time
> distillation. Keep it under 12,000 characters: past that it is cut (`bin/repo-guards` fails).

## Stack

`zsv` is a RubyGems gem: a CSV parser for Ruby implemented as a C extension over the
[zsv](https://github.com/liquidaty/zsv) C library (SIMD). It is loaded into the user's process, so
a bug in the C is a segfault, memory corruption or a leak in their application, not an exception.

- `ext/zsv/*.c`, `*.h`: our C. `parser.c` bridges zsv's callback (push) API to Ruby's pull API
  (`shift`, `each`) through a row buffer; `row.c` turns cells into Ruby Arrays / Hashes;
  `options.c` converts the options Hash; `zsv_ext.c` defines `ZSV`, `ZSV::Parser`, the error
  classes and the TypedData (mark / free / size / compact) functions.
- `ext/zsv/vendor/zsv/`: the vendored zsv source, exactly what `rake zsv:vendor` extracts from
  the tarball pinned in `ext/zsv/ZSV_UPSTREAM` (version + SHA-256). `ext/zsv/extconf.rb` builds
  it into a static library, offline. Not reviewed line by line: reviewed by pin and hash.
- `lib/zsv.rb`, `lib/zsv/`: the Ruby surface (`ZSV.foreach`, `parse`, `read`, `open`, `new`).
- `spec/`: RSpec, including parity specs against Ruby's `CSV`. `benchmark/`: benchmark-ips runs.
- Gem version mirrors zsv: gem X.Y.Z wraps zsv X.Y.Z.

## What to reject

**GC safety (HIGH when a trigger is named)**
- A `VALUE` stored in the parser struct, a row builder or any heap memory that the TypedData
  mark function does not mark (or, with compaction support, does not update). Trigger: a GC
  between two `shift` calls frees the row buffer, headers or a header String.
- A `VALUE` kept only in a C local across a call that can allocate or run Ruby code, when the
  compiler may drop it from the stack (a `RSTRING_PTR` / `RARRAY_PTR` taken, then the VALUE never
  used again) and no `RB_GC_GUARD` follows the last use of the pointer.
- Any Ruby allocation, `rb_raise`, `rb_funcall` or `rb_yield` reachable from the free function
  (`dfree` → `zsv_parser_free` → release). Allocating during GC crashes the VM. `zsv_finish`
  fires row callbacks, so a `zsv_finish` call added to close, free or release is this bug.
- A raw pointer into a Ruby String (`RSTRING_PTR`) kept across calls, or read from a String that
  is not held (marked) and frozen for as long as the parser reads from it: the user can mutate
  or free the bytes under the parser, and compaction can move them.
- A `VALUE` field marked with `rb_gc_mark_movable` and not updated in the compact function, or
  `RUBY_TYPED_WB_PROTECTED` added while VALUEs are stored without `RB_OBJ_WRITE`.
- `rb_gc_register_address` / `rb_global_variable` missing for a `VALUE` held in a C global.

**Exceptions and resources**
- `rb_raise`, or a block that raises through `rb_yield`, or a non-local exit (`break`, `throw`)
  between acquiring and releasing a `FILE *`, a `zsv_parser`, or `malloc`/`xmalloc` memory, with
  no `rb_ensure` / `rb_protect` and no owner that the free function will clean up. Name the
  leaked resource.
- `rb_raise`, or any Ruby call that can raise (allocation, `rb_funcall`, a conversion), in a zsv
  callback (row, overflow, read) outside `rb_protect`: it longjmps through zsv's C frames and
  leaves the zsv parser mid-buffer. The callback records the `rb_protect` state and returns;
  the driver releases the parser and re-raises with `rb_jump_tag` after `zsv_parse_more` returns.
- `malloc` / `calloc` / `strdup` unchecked for NULL; `xmalloc` memory freed with `free` or the
  reverse.
- A module method (`ZSV.foreach`, `ZSV.open` with a block, `ZSV.read`, `ZSV.parse`) that can
  return or raise without closing the parser it opened.

**zsv lifecycle**
- `zsv_finish` reachable twice for one `zsv_parser`, or not at all before `zsv_delete` on a path
  that still expects the final row (input without a trailing newline). It runs exactly once: at
  EOF in `shift`, or in close, never both.
- `zsv_delete` reachable twice (close then free, rewind then close), or any zsv call on a parser
  after `zsv_delete` or after close. `closed` must be checked first by every method.
- A pointer from `zsv_get_cell` used after the row callback returns or after the next
  `zsv_parse_more`: zsv reuses that buffer. Cell bytes are copied into a Ruby String inside the
  callback.
- Ignoring the `enum zsv_status` of `zsv_parse_more` / `zsv_finish`: anything other than ok /
  no-more-input is an error the user must see.

**Memory and integers**
- Indexing or `memcpy` with a length that came from input without a bound check; growth
  arithmetic (`capacity * 2`, `n * sizeof`) that can overflow; `size_t` narrowed to `int` /
  `long` (or the reverse with a negative value) without a range check. Option values from Ruby
  (`skip_lines`, `buffer_size`) are validated before conversion: negative, zero and huge.
- `StringValueCStr` missing where a path goes to `fopen` (embedded NUL), or a `char *` kept
  across a call that can move or free the String.
- A multi-byte `col_sep` / `quote_char` silently truncated to its first byte.
- Encoding: a String created without the configured encoding, or a claim of valid UTF-8 for
  bytes never checked when the docs promise validation.

**Threads and reentrancy**
- A method that reaches zsv without the `parsing` reentrancy check (an IO source whose `#read`
  calls back into the parser, a second thread), or `each` touching state after a yield without
  re-checking `closed` (the block may `close` or `rewind`). Name the sequence.
- Releasing the GVL (`rb_thread_call_without_gvl`) around code whose callback touches Ruby
  objects.

**Parity with CSV (the product's contract)**
- A documented option (`headers`, `col_sep`, `quote_char`, `skip_lines`, `liberal_parsing`, …)
  whose rows differ from `CSV`'s for the same input and option, with no documented difference
  in `docs/API_REFERENCE.md`. A new option without a parity spec comparing against `CSV`'s own
  output. An option accepted and silently ignored: unsupported options raise `ArgumentError`.
- A changed row for an existing input (empty fields, quoted newlines, CRLF, BOM, ragged rows,
  duplicate headers, no trailing newline) without a spec asserting it and a CHANGELOG line.

**Build and supply chain**
- Anything in `extconf.rb`, the Rakefile or the gemspec that downloads at install or compile
  time, links a system libzsv, or reads the zsv version from anywhere but
  `ext/zsv/ZSV_UPSTREAM`.
- A hunk under `ext/zsv/vendor/` in a PR that does not also change `ext/zsv/ZSV_UPSTREAM`: the
  vendored tree is never edited by hand.
- A `ZSV_UPSTREAM` change without the re-vendored tree, a CHANGELOG entry and before/after
  `rake bench` output in the PR body, or with a SHA-256 that is not the upstream tag tarball's.
- A host-specific flag (`-march=native`, `-mavx2`) reaching the portable path of `extconf.rb`
  (`--enable-portable`, `ZSV_PORTABLE=1`, every cross-build of a precompiled gem): that gem dies
  with SIGILL on another CPU. `-w` or a `#pragma` silencing a warning instead of fixing it.
- A new file the gemspec's `spec.files` does not match (it would not ship), or a shipped file
  that is not needed to build.
- A new runtime dependency in `zsv.gemspec`.

**Releases and docs**
- A release by hand: a pushed `v*` tag, `rake release`, `gem push`. Merging a
  `lib/zsv/version.rb` bump to `main` is the release; a release PR changes only the version,
  `Gemfile.lock`'s own version line and CHANGELOG.
- A gem version whose first three segments are not the pinned zsv version.
- A speedup or memory claim ("Nx faster") added to README, the gemspec or docs with no
  benchmark output it can be traced to; a hardcoded Ruby / OS support list (the CI matrix owns it).
- A user-visible change with no `## [Unreleased]` CHANGELOG line, or a behaviour change that
  leaves `README.md`, `docs/API_REFERENCE.md` or `llms.txt` stale.
- `skip` / `pending` / `xit`, a deleted failing spec, a loosened `.rubocop.yml` or
  `.clang-format`, or `continue-on-error` in a gating CI job.

## Proof a C finding needs

Before posting HIGH on C: the exact line, the sequence that triggers it (which Ruby calls, in
which order, where the GC or the exception happens), and why the existing guard (the mark
function, a `closed` check, an `rb_ensure`) does not cover it. Read the TypedData definition in
`zsv_ext.c` and the callers first. A lifetime bug you can describe but not place on a line is
a question, not a finding. One false positive costs more than one missed nit; zero findings is
a valid review.

## Gates that matter

- The one required check is CI's aggregate `CI OK` job (`.github/workflows/ci.yml`). Every job
  under it must pass, including the ASan + UBSan build; none may `continue-on-error`.
- Locally `bin/check` runs the repo guards, RuboCop, clang-format, the compile and the suite; it
  exits 75 (could not grade) when the environment is missing. A change that has not passed it
  is not proven. A C lifetime change is proven by a spec that runs under `GC.stress`.
- `canary.yml` (monthly: Ruby head, zsv upstream) and `benchmark.yml` are not gating.

## Never flag

- Style in C or Ruby: `.clang-format` and `.rubocop.yml` own it, CI enforces both.
- Anything inside `ext/zsv/vendor/` line by line (warnings, style, `TODO`s): it is upstream's.
- `rb_str_freeze` on returned field Strings, or rows returned as frozen Strings in plain
  `Array`s / `Hash`es rather than `CSV::Row`: by design, documented.
- `xmalloc` / `RB_ALLOC` results not checked for NULL: they raise `NoMemoryError` instead.
- A source build targeting the build machine's CPU by default: by design; `--enable-portable`
  is the documented opt-out.
- The parser type not being write-barrier protected: by design, it is always rescanned.
- Hardcoded CSV inputs and expected rows in specs; `GC.stress` / `GC.compact` loops in specs.
- Benchmarks comparing against the `csv` gem version in `Gemfile.lock`: that is the baseline.
- A red monthly `canary.yml` or a benchmark delta inside run-to-run noise.
- "Add Windows support": not in the matrix by design until the vendored build runs through mkmf.
