# ext/ — the C extension

This code is loaded into the user's process. A mistake is not an exception: it is a segfault, memory corruption or a leak in their application. Read this before editing `ext/zsv/*.c` or `*.h`; review with agent `c-safety-reviewer`; debug with skill `debug-gc`.

## Map

| File | Owns |
|---|---|
| `zsv/zsv_ext.c` | `Init_zsv`: `ZSV`, `ZSV::Parser`, the error classes. The `rb_data_type_t` (`dmark`, `dfree`, `dsize`, `dcompact`), the alloc function, every `rb_zsv_*` method. Thin: it unwraps and delegates |
| `zsv/parser.c`, `parser.h` | `zsv_ruby_parser_t` and the **callback → pull bridge**: zsv callbacks (row, read, errprintf), setup per source kind (file, String, IO), `shift`, `rewind`, close / release, mark / compact |
| `zsv/row.c`, `row.h` | `zsv_row_builder_t`: copies cell bytes into Ruby Strings, builds the `Array` or `Hash` row, holds the header copy |
| `zsv/options.c`, `options.h`, `options_internal.h` | The options Hash → `zsv_ruby_options_t`. Validation that needs Ruby semantics lives in `lib/zsv/options.rb`; the C side still range-checks everything it converts |
| `zsv/common.h` | Shared includes, class `VALUE` externs, error macros |
| `zsv/extconf.rb`, `upstream.rb`, `ZSV_UPSTREAM` | The build: copies the vendored zsv to a private build dir, `./configure --minimal` + `make`, links `libzsv.a` statically. Offline. Owner-only |
| `zsv/vendor/zsv/` | The pinned zsv source (`LICENSE`, `configure`, `include`, `src`, marker `VENDORED_FROM`). **Never edit.** Written by `rake zsv:vendor` only |

## The bridge

zsv pushes: `zsv_parse_more()` reads one buffer and calls our row handler once per row. Ruby pulls: `shift` returns one row. So the row handler appends rows to `parser->row_buffer` (a Ruby Array), and `shift` returns from the buffer, calling `zsv_parse_more()` again only when it is empty. At end of input `zsv_finish()` flushes the final row (input with no trailing newline).

Our Ruby-calling code therefore runs **underneath zsv's C frames**. That fact drives most rules below.

## Rules

**GC**

1. Every `VALUE` stored in `zsv_ruby_parser_t`, `zsv_row_builder_t` or `zsv_ruby_options_t` is marked in `zsv_parser_mark` (it calls `zsv_row_builder_mark`) and, because marks are movable (`rb_gc_mark_movable`), updated in `zsv_parser_compact`. Add a field → add both lines in the same commit, and a spec that survives `GC.stress` and `GC.verify_compaction_references`.
2. The type is **not** write-barrier protected (no `RUBY_TYPED_WB_PROTECTED`): VALUEs are stored in C memory without `RB_OBJ_WRITE`. Do not add the flag without converting every store.
3. A `VALUE` whose raw pointer (`RSTRING_PTR`, `RARRAY_CONST_PTR`) is used after its last use as a VALUE needs `RB_GC_GUARD` after the pointer's last use. Re-read `RSTRING_PTR` after anything that can allocate or compact; never cache it across calls.
4. The free path (`dfree` → `zsv_parser_free` → release) **never calls into Ruby**: no allocation, no `rb_raise`, no `rb_funcall`. `zsv_delete()` does not fire callbacks and `zsv_finish()` is never called from free or close, so no Ruby code is reachable there. Keep it that way.
5. Memory comes from `xmalloc` / `RB_ALLOC` family (`ZSV_ALLOC*` macros) and is freed with `xfree`. They raise `NoMemoryError` instead of returning NULL, so the caller must already be leak-safe at that point. `dsize` reports what we allocate.

**Exceptions**

6. **Never let an exception unwind through zsv.** Every callback zsv invokes (row handler, overflow handler, read callbacks) runs its Ruby-touching body under `rb_protect`, stores the state in `parser->exception_state`, and returns normally; later callbacks in the same chunk return early. After `zsv_parse_more()` returns, our code releases the parser and re-raises with `rb_jump_tag`. A bare `rb_raise` or an unprotected `rb_funcall` in a callback is a bug.
7. Acquire OS resources last. Options are parsed and Ruby-side state allocated before `fopen`; the struct belongs to the Ruby object from `alloc` on (`TypedData_Make_Struct`), so a raise during `initialize` is cleaned up by `dfree`. New resource → released in the one release function, which must stay idempotent.
8. Between acquiring something no owner will free and releasing it, nothing may raise: `StringValue`, `NUM2*`, `rb_funcall`, `rb_yield`, allocation all can. Convert and validate first.
9. `rb_yield` (in `each`) happens in our frames with the parser in a consistent state: the block may raise, `break`, or call `close` on the parser. The loop re-checks `closed` after every yield.

**zsv lifecycle**

10. `zsv_finish()` runs **exactly once** per zsv parser: at EOF (`zsv_status_no_more_input`) inside the one function that drives `zsv_parse_more()`, never when a callback recorded an exception, never from close, free or rewind. `eof_reached` records it.
11. `zsv_delete()` and `fclose()` each run exactly once, in release, which NULLs the pointers. Every public method checks `closed` first; rewind deletes and recreates the zsv parser and resets all per-pass state.
12. `parser->parsing` is the reentrancy guard: set around the zsv call, checked by `shift`, `close` and `rewind`. A parser re-entered from its own callback (an IO source whose `#read` uses the parser) or from another thread raises `ZSV::Error` instead of corrupting zsv.
13. Check every `enum zsv_status`. Anything but `ok` / `no_more_input` is a `ZSV::MalformedCSVError` carrying `zsv_parse_status_desc`.
14. zsv writes warnings through `errprintf`: ours is silent and turns the ones that mean data loss (a row wider than `max_columns`, a row cut short because it filled the buffer) into errors. The buffer holds `max_row_size + 1` bytes and the row handler raises for a longer row (`zsv_row_length_raw_bytes`), so no row is returned incomplete. Do not use `overflow_row_handler`: zsv 1.4.4 passes it its scanner, not our `ctx`. Never let zsv print to the user's stderr, never drop data silently.

**Pointers and integers**

15. Bytes from `zsv_get_cell()` are valid only inside the row callback: copy them into a Ruby String there (`row.c`). Never store the pointer.
16. A String source is read through a frozen copy held in `parser->source` (marked), with an offset, re-reading `RSTRING_PTR` on each read callback. An IO source is called through `rb_protect`, and the chunk length is checked against what was requested before `memcpy`.
17. Lengths are `size_t` (zsv) or `long` (Ruby). Check before narrowing either way; check growth arithmetic for overflow; option values (`skip_lines`, `buffer_size`, `max_columns`, `max_row_size`) are range-checked before they reach `struct zsv_opts`.
18. Paths go through `FilePathValue` (rejects embedded NUL, handles `Pathname`).
19. Returned field Strings carry the configured encoding and are frozen.

**Threads**

20. The GVL is held for the whole parse. Do not release it (`rb_thread_call_without_gvl`) around zsv: its callbacks touch Ruby objects. Interrupts are checked between chunks (`rb_thread_check_ints`), outside zsv.

**Build**

21. `-std=c99 -Wall -Wextra`; a new warning is fixed, not silenced. Style is `.clang-format` (LLVM base, 4 spaces, 100 columns, Linux braces): `clang-format -i ext/zsv/<file>`; CI fails on a diff. The vendored tree is exempt.
22. Every build targets the architecture's baseline CPU (SSE2 / NEON, zsv's SIMD scanner still on) by default, source builds included: a binary built on one CPU (a Docker image built in CI) must not die with SIGILL on another. `--enable-native` (or `ZSV_NATIVE=1`) opts a source build into `-march=native`; cross-builds (the precompiled gems) ignore it. Never add a host-specific flag to the default path.
23. `extconf.rb` never downloads and never links a system libzsv. The zsv version comes from `ZSV_UPSTREAM` only.
24. A new `.c` / `.h` is picked up by mkmf and by `spec.files` (`ext/zsv/*.{c,h,rb}`); anything else must be added to the gemspec or it does not ship.

## Proving a C change

1. A spec that fails first. Lifetime change → the path under `GC.stress = true`; a new VALUE field → also compaction.
2. `bin/check` (clang-format, compile with warnings, suite).
3. `bin/check asan` (ASan + UBSan; Linux). CI's `sanitizers` job runs it on every PR.
4. Hot path (`zsv_row_handler*`, `row.c`) → `bundle exec rake bench` before and after, both in the PR body.
5. Paths to walk by hand for anything touching lifetime: close twice · close inside `each` · `break` out of `each` · raise from the block · raise from an IO's `#read` · rewind then read then close · drop the parser unclosed and `GC.start` · empty input · no trailing newline · a row wider than `max_columns`.

## Never

- Edit `ext/zsv/vendor/`, or work around a zsv bug by patching it. Report upstream; adapt in our C with a spec if possible.
- `rb_raise` / unprotected Ruby calls inside a zsv callback; Ruby calls on the free path.
- `GC.disable`, `rb_gc_register_address` on per-parser state, or a `volatile` sprinkled in to make a crash go away.
- Call `zsv_finish()` anywhere but the EOF branch.
- Change the pin by hand (skill `upgrade-zsv`).
