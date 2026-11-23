---
name: verify-change
description: Use when proving a change in zsv-ruby before a commit or pull request, when bin/check, rspec, rubocop, clang-format or the compile fails, when a script exits 75, or when asked how to run the tests, the linter, the sanitizers or the benchmarks.
---

# Verify a change

`bin/check` is the gate. CI runs the same script, so green locally is green there (for the Ruby and OS you ran it on; CI adds the matrix).

| Tier | Command | Scope | When |
|---|---|---|---|
| named files | `bin/check files <paths>` | rubocop on the Ruby ones, clang-format on `ext/zsv/*.{c,h}`, rspec on the `*_spec.rb` ones. **Never compiles.** | the only tier allowed when agents share the checkout |
| fast | `bin/check fast` | `bin/repo-guards` + rubocop and clang-format on files changed against `origin/main` + incremental compile + specs not tagged `:slow` | after each edit |
| full | `bin/check` | `bin/repo-guards` + rubocop + clang-format + compile + full rspec | once, before the PR |
| sanitizers | `bin/check asan` | clean rebuild with ASan + UBSan, full rspec with the runtimes preloaded, clean rebuild of the normal extension. Linux + gcc | every change to `ext/zsv/*.{c,h}`, every zsv upgrade |
| benchmarks | `bundle exec rake bench` | `benchmark/*_bench.rb` against the `CSV` stdlib | hot-path change (`parser.c`, `row.c`), zsv upgrade, any speed claim: before and after |

Other commands: `bin/setup` (install + compile, idempotent) · `bin/console` (IRB with `ZSV` and `CSV`) · `bin/repo-guards` (the guards alone) · `bundle exec rake zsv:verify` (vendored tree = pinned tarball; needs network).

## Exit codes

| Exit | Means | Do |
|---|---|---|
| 0 | green | commit. `GREEN (NOT GRADED: clang-format)` means clang-format is not installed here: CI grades it |
| 75 | environment missing — Ruby, gems, a C compiler, the compiled extension, gcc's sanitizer runtimes; nothing was graded | `bin/setup`, rerun. Never treat it as a failing change, never as a pass. |
| other | a check ran and is red | read the `failing command` / `rerun` lines at the end of the output |

## Rules

1. Run from anywhere; the scripts `cd` to the repo root and select the Ruby in `.ruby-version` themselves (`ZSV_ANY_RUBY=1` uses the active Ruby instead).
2. Changed `Gemfile`, `zsv.gemspec`, `ext/zsv/extconf.rb` or `ext/zsv/ZSV_UPSTREAM` → `bin/setup` before `bin/check`. Changed `extconf.rb` or a header and the build looks stale → `bundle exec rake clean`, then `bin/check`.
3. **One compiled artifact.** `lib/zsv/zsv.so` is built through `tmp/`; two compiles at once in one checkout corrupt each other. Sharing the checkout → `bin/check files …` only, and one agent owns the build.
4. Fail one, fix one: rerun only the failing step (`bundle exec rspec --only-failures`, `bundle exec rspec spec/zsv_spec.rb:LINE`, `bundle exec rubocop -a <file>`, `clang-format -i <file>`), then the tier.
5. Write the failing spec first — a green run that never went red proves nothing.
6. A C change is not proven by a green suite alone: `bin/check asan`, and a spec that runs the changed path under `GC.stress = true` (skill `debug-gc`).
7. A changed row for an existing input → assert it in a spec against `CSV`'s output for the same input and option.
8. A segfault (`[BUG] Segmentation fault`), an abort, or a failure that comes and goes → skill `debug-gc`. Never retry until green.
9. Red gate → fix the cause. Never add `rubocop:disable`, `// clang-format off`, `-w`, loosen `.rubocop.yml` / `.clang-format`, or mark a spec `skip` / `pending` to get to green.
10. Never trust a piped exit code: `bin/check | tail` reports `tail`. Run it bare, or read `${PIPESTATUS[0]}`.
11. Never quote a benchmark number you did not just measure; give the Ruby version and CPU with it.
