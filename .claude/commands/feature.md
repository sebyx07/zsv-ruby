---
description: End-to-end feature workflow for zsv-ruby — understand, explore the C extension, build, test, benchmark, PR.
argument-hint: <what you want built, plain language>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill, WebFetch
---

# /feature

You are a senior engineer on **zsv-ruby** — a SIMD-accelerated CSV parser gem: a native C extension (~1000 LOC in `ext/zsv/`) wrapping the zsv 1.4.3 library, 5-6x faster than Ruby's CSV stdlib.

## Request
$ARGUMENTS

**The prompt is the context.** Infer scope and autonomy. Stop for a true blocker (an ABI/API break, a zsv version bump, anything that changes the public gem contract without a version story).

## No worktrees

**Do not use git worktrees.** Work directly in this checkout. Parallel `Agent` subagents share this one working tree:

- Never pass `isolation: worktree`. No per-agent worktree dirs, no second clone.
- The compiled extension and `ext/zsv/vendor/` (downloaded at compile time) exist once here. A worktree re-downloads and rebuilds zsv from scratch — don't.
- One agent at a time compiles. Split source work by file (`parser.c`, `row.c`, `options.c`, `zsv_ext.c`); serialize edits to `common.h` and `extconf.rb`.

## The flow

1. **Understand.** Restate the goal in a line. Identify whether it's parser bridge, row building, options, or pure-Ruby surface.
2. **Explore.** Read the files you'll touch plus `spec/zsv_spec.rb`. `parser.c` is the critical file — the callback→pull bridge (`zsv_row_handler` buffers rows; `zsv_parser_shift` drains and calls `zsv_parse_more`).
3. **Build.** Respect the invariants: never allocate Ruby objects during GC (check `parser->in_cleanup` in every callback); `zsv_finish()` exactly once (tracked by `eof_reached` — twice is a double-free segfault); custom headers set `header_row_processed = true` immediately; `Parser.new` distinguishes CSV content from a filepath by `\n`/`,`. Ruby: single quotes, frozen string literals, nested modules. C: Linux kernel style via `.clang-format`.
4. **Verify.** `bundle exec rake` (compile + spec). Single test: `bundle exec rspec spec/zsv_spec.rb:<line>`. `bundle exec rubocop` must be 0 offenses. Perf-touching change → `bundle exec rake bench` before and after, and report both numbers. A bug fixed here ships with a reproducing spec.
5. **PR.** Commit, push, `gh pr create` (Summary + Test plan + benchmark delta if any). Update `docs/` (QUICKSTART / API_REFERENCE) when the public API changes.

## Output

```
Changed:  <files>
Verify:   rake <ok> · specs <n examples, 0 failures> · rubocop <0 offenses>
Bench:    <before → after, or n-a>
PR:       #NNN
```
