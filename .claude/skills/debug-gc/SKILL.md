---
name: debug-gc
description: Use when zsv-ruby segfaults, aborts, or fails intermittently — "[BUG] Segmentation fault", double free, heap-use-after-free, "object allocation during garbage collection phase", a T_NONE or wrong-class row, corrupted strings, a spec that fails only sometimes or only on one platform, a leak — and when reviewing or changing object lifetime in ext/zsv/*.c.
---

# Debug a GC or memory bug in the C extension

An intermittent crash here is almost always one of five things. Make it deterministic first; read code second.

## 1. Make it fail every time

Write the smallest spec (or `tmp/repro.rb` run with `bundle exec ruby -Ilib tmp/repro.rb`) that walks the suspect path, then turn the screws one at a time:

| Tool | How | Catches |
|---|---|---|
| GC stress | `GC.stress = true` around the calls (`ensure GC.stress = false`) | a `VALUE` nobody marks; a `VALUE` held only in a C local across an allocation |
| Compaction | `GC.verify_compaction_references(expand_heap: true, toward: :empty)` between `shift` calls (skip when `GC.respond_to?(:compact)` is false) | a marked `VALUE` whose address is cached, or marked with `rb_gc_mark_movable` and never updated in `dcompact` |
| Free path | open parsers, drop them without `close`, `GC.start`; also `close` twice, `close` inside `each`, `rewind` then `close`, `break` out of `each` | double `zsv_delete` / `fclose`, a callback allocating during free, a use after close |
| Raise path | raise from the block given to `each` / `foreach` / `open`; pass bad options; a missing file | a leaked `FILE *` / `zsv_parser`, state left half-initialised |
| Sanitizers | `bin/check asan` (Linux; the suite under ASan + UBSan, then the normal build is restored) | use after free, overflow, double free, with the allocating and freeing stacks |
| Leak | loop the path 100k times, `GC.start`, compare `` `ps -o rss= -p #{$$}`.to_i `` before and after | memory or file descriptors (`ls /proc/$$/fd \| wc -l`) that grow without bound |

One spec file under ASan by hand (after `bin/check asan` has failed, rebuild instrumented first):

```bash
bundle exec rake clean
bundle exec rake compile -- --with-cflags="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1" --with-ldflags="-fsanitize=address,undefined"
LD_PRELOAD="$(gcc -print-file-name=libasan.so):$(gcc -print-file-name=libubsan.so)" \
  ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:use_sigaltstack=0 bundle exec rspec spec/zsv_spec.rb:LINE
bundle exec rake clean compile      # ALWAYS restore: an instrumented .so aborts without LD_PRELOAD
```

A core dump or `[BUG]` report: the "C level backtrace" section names our frame; `gdb --args $(bundle exec which ruby) -Ilib tmp/repro.rb`, then `run`, `bt`.

## 2. Match the symptom

| Symptom | Usual cause | Look at |
|---|---|---|
| crash or garbage row only under `GC.stress` | a `VALUE` in the parser struct or row builder that the mark function skips; or a `VALUE` created, then only its `RSTRING_PTR` used across an allocating call (needs `RB_GC_GUARD`) | the TypedData `dmark` in `ext/zsv/zsv_ext.c` vs every `VALUE` field in `ext/zsv/parser.h`, `row.h`, `options.h` |
| `object allocation during garbage collection phase`, or a crash inside `dfree` | something on the free path calls into Ruby: a `zsv_finish` reachable from release (it fires the row callback, which allocates), or an allocation / raise added to free | `zsv_parser_free` and the release function in `parser.c`: no Ruby calls, no `zsv_finish` |
| double free / `free(): invalid pointer` at close or exit | `zsv_finish` or `zsv_delete` reached twice (EOF then close; rewind then close; close then free), or `fclose` twice | every caller of `zsv_finish`, `zsv_delete`, `fclose`; the flags that guard them |
| last row missing, or delivered twice | `zsv_finish` not called at EOF (no trailing newline), or called twice | the EOF branch of the shift function |
| heap-use-after-free on cell bytes | a `zsv_get_cell` pointer kept after the callback returned | `row.c`: bytes are copied into a Ruby String inside the callback |
| wrong data when the source String is mutated, moved or collected | the parser reads a String it does not hold frozen and marked, or caches `RSTRING_PTR` across calls (compaction moves it) | the String source in `parser.c`: frozen copy in `parser->source`, pointer re-read per read callback |
| crash after an exception (in a block, in an IO's `#read`, on a bad row) | `rb_yield` raised past C state that assumed it would return; or a Ruby call in a zsv callback ran outside `rb_protect` and longjmp'd through zsv's frames | `each`; the callbacks in `parser.c`: body under `rb_protect`, state in `exception_state`, re-raised with `rb_jump_tag` after `zsv_parse_more` returns and the parser is released |
| only on one platform | a SIMD path (x86_64 AVX2 vs SSE2 vs arm64 NEON; the default build is the baseline, `ZSV_NATIVE=1` the host CPU), `char` signedness (ARM), struct padding, `long` vs `size_t` | `gh run view <id> --log-failed`; reproduce the input, not the platform |
| only on Ruby head | a C API changed or was removed | the canary log; `ruby/doc/extension.rdoc`, NEWS for that version |

## 3. Fix, then prove

1. The reproducing spec fails first, for the right reason. Keep it in `spec/` (GC-stress loops are slow: tag them `:slow` when they take more than a second; `bin/check` runs them, `bin/check fast` does not).
2. Fix the cause in our C (`ext/CLAUDE.md` has the rules). Never fix by `GC.disable`, by `rb_gc_register_address` on per-object state, by catching the signal, or by editing `ext/zsv/vendor/`.
3. `bin/check` green, `bin/check asan` clean, the repro loop stable for 1000 iterations under `GC.stress`.
4. Hot path touched → `bundle exec rake bench` before and after.
5. CHANGELOG `### Fixed`: what crashed, for which input or call sequence.

## Never

- Never retry a flaky spec until it passes, mark it `skip`, or lower an iteration count to hide it.
- Never report "could not reproduce" without listing which rows of the table in §1 you ran.
- Never leave the instrumented build in `lib/zsv/`: finish with `bundle exec rake clean compile`.
