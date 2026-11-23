---
description: Sweep one area of zsv-ruby for defects — run the detectors below, fix each with a failing spec first, ship one goal-scoped pull request. Use for bug sweep, find bugs, fix everything in, QA pass.
argument-hint: <the area or goal to sweep, e.g. "IO sources" or "headers">
---

Sweep `$ARGUMENTS` for defects. A clean area reported clean is a success: never invent a defect to have something to ship, never fix what is not broken. Read `CLAUDE.md` first, and `ext/CLAUDE.md` when the area reaches `ext/`: their invariants bind every fix.

## Steps

1. Read the area and every route into it (`foreach`, `parse`, `read`, `open`, `Parser#shift` / `each`; a path, a String and an IO source take different routes through the C), then run each detector below over it. Read the code that does the thing, not only a file that mentions it.
2. For each defect: write the failing spec first and watch it fail, then fix the cause. A wrong row is asserted against `CSV`'s own answer (`csv_rows` in `spec/api/csv_compat_helper.rb`), never a literal. A crash or a lifetime bug is reproduced under `GC.stress = true` or by `bin/check asan` (skill `debug-gc`).
3. A defect class that recurred is fixed as a class: an input added to the shared table in `spec/api/csv_compat_spec.rb`, a GC-stress spec, or a guard that makes the next one fail, in the same change.
4. Prove it with `bin/check`; a change to `ext/zsv/*.{c,h}` also needs `bin/check asan` and agent `c-safety-reviewer` (skill `verify-change`). Exit 75 is a missing environment, not a result: `bin/setup`. One compile at a time in the checkout. Red is not a pull request: fix the cause, never silence the check.
5. Ship one goal-scoped pull request for the area, every defect in it with its spec, and a `CHANGELOG.md` `## [Unreleased]` line for what users see. A defect outside the area is its own pull request, named in the body.
6. The body lists each defect: the input and options that broke it, the spec that pins it, the fix, and what each gate printed.

A fix that changes the rows returned for an input that parsed before, an option's default or the public API is breaking: report it and stop for the owner. A defect in `ext/zsv/vendor/` is upstream's: report it there, never edit the tree.

## What to hunt — run the detector, do not just read

| Class | Detector |
|---|---|
| Stored `VALUE` the GC cannot see or move | each `VALUE` field of `zsv_ruby_parser_t`, `zsv_row_builder_t`, `zsv_ruby_options_t` has a line in the mark and in the compact function; run the path under `GC.stress` and `GC.verify_compaction_references` |
| Raw pointer outliving its object | `RSTRING_PTR` / `zsv_get_cell` bytes used after a call that allocates, runs Ruby or advances the parser; `bin/check asan` |
| Exception unwinding through zsv | Ruby-touching code in a zsv callback outside `rb_protect`; a raising `#read` and a raising block, under `bin/check asan` |
| Leak or double release | close twice, close inside `each`, `break`, a raising block, a raising option, a second `#initialize`, a parser dropped unclosed then `GC.start` |
| `zsv_finish()` not exactly once | input with no trailing newline, then close, rewind and free paths |
| Rows that differ from `CSV` | the awkward inputs of `spec/CLAUDE.md` rule 2 through every entry point, compared with `csv_rows` |
| Data dropped silently | a row longer than the buffer, wider than `max_columns`, an ignored `enum zsv_status` |
| Option accepted and ignored | every key and value `docs/API_REFERENCE.md` does not list raises `ArgumentError` |
| Integer narrowing or overflow | `size_t` / `long` / `int` conversions and growth arithmetic with no range check; UBSan in `bin/check asan` |
| A doc, example or `llms.txt` line the code no longer matches | run the snippet in `bin/console`; read the sentence against `lib/zsv/options.rb` |
| Spec that proves nothing | break the guarded thing; if the spec stays green, the spec is the bug |
| Missing spec | an option, entry point or error path the area has that no spec exercises |
