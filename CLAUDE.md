# CLAUDE.md

Guidance for agents in this repository. **Budget: under 12,000 chars** (`bin/repo-guards` fails past it; the developerz.ai loader cuts the rest). Move detail down, never raise the cap:

| Touching | Also read (auto-loads there) |
|---|---|
| `ext/` | [`ext/CLAUDE.md`](ext/CLAUDE.md): the C rules (GC, exceptions, zsv lifecycle, pointers, build) |
| `spec/` | [`spec/CLAUDE.md`](spec/CLAUDE.md): parity specs, GC-stress specs, `:slow` |
| `.github/`, `RELEASE.md`, `lib/zsv/version.rb` | [`.github/CLAUDE.md`](.github/CLAUDE.md): CI jobs, canary, release lane |

`AGENTS.md` is a symlink to this file. User-facing reference: `README.md`, `docs/API_REFERENCE.md`, `llms.txt`. Intent and direction (draft): `docs/idea/`, index `docs/README.md`.

## zsv-ruby

Ruby gem `zsv` (`zsv.gemspec`; version in `lib/zsv/version.rb`): a CSV **parser** with the reading API of Ruby's `CSV` (`ZSV.foreach`, `parse`, `read`, `open`, `ZSV::Parser#shift` / `each`), implemented as a C extension over the SIMD [zsv](https://github.com/liquidaty/zsv) C library. It runs inside the user's process: a bug in the C is a crash or corrupted memory in their application.

## Invariants

All must stay true. 1 to 4 are detailed, with their rules, in `ext/CLAUDE.md`.

1. **GC safety.** Every `VALUE` held in C memory (parser struct, row builder, options) is marked and, since marks are movable, updated on compaction. The free path never calls into Ruby. A new field means a mark line, a compact line and a spec under `GC.stress`.
2. **Callback → pull bridge.** zsv pushes rows through a callback during `zsv_parse_more()`; Ruby pulls with `shift`. The callback appends to a row buffer, `shift` drains it and parses another chunk only when it is empty. Callbacks run under zsv's C frames, so **no exception may unwind through zsv**: Ruby code in a callback runs under `rb_protect`, and the recorded exception is re-raised after zsv returns and the parser is released.
3. **`zsv_finish()` exactly once** per zsv parser, at end of input (it flushes a final row with no trailing newline). Never from close, free or rewind, never twice. `zsv_delete()` and `fclose()` exactly once, in the one release function.
4. **No leaks on any path.** A raise from options, from an IO's `#read`, from the block given to `each` / `foreach` / `open`, a `break`, a double `close`, a parser dropped unclosed: none may leak a `FILE *`, a zsv parser or memory, and none may crash. Module methods close what they open in `ensure`.
5. **Parity with `CSV` for documented options.** For every option `docs/API_REFERENCE.md` lists as compatible, the rows equal what Ruby's `CSV` returns for the same input, and the parity specs compare against `CSV`'s own output, never a literal. Each intended difference is listed in `docs/API_REFERENCE.md` and `llms.txt`. An unsupported option or value raises `ArgumentError`; nothing is accepted and ignored.
6. **Version sync.** Gem `X.Y.Z` ships zsv `X.Y.Z`. A gem-only release appends a fourth segment (`X.Y.Z.1`). The pin may be ahead of the gem between a zsv upgrade and its release; the gem is never ahead of the pin (`bin/repo-guards`).
7. **Vendored, pinned, offline.** `ext/zsv/ZSV_UPSTREAM` holds the zsv version and the SHA-256 of its upstream tarball. `ext/zsv/vendor/zsv/` is exactly what `rake zsv:vendor` extracts from that verified tarball (`rake zsv:verify` proves it) and ships inside the gem. `gem install` and `rake compile` never touch the network and never link a system libzsv.
8. **Honest numbers.** No speedup or memory figure in README, docs or the gemspec that a reproducible benchmark run does not show. `benchmark.yml` posts every `main` push's `rake bench` output; docs point there.

Floors and platforms: the Ruby floor is `required_ruby_version` in the gemspec; the dev Ruby is `.ruby-version`; tested Rubies, OSes and architectures are the matrix in `.github/workflows/ci.yml`. Never restate them in docs.

## Never

- Use git worktrees (`git worktree add`, `isolation: worktree`, a second clone). Work in this checkout; parallel agents split into disjoint file sets.
- `git add -A` / `git add .` / `git stash`. Stage by path: the tree may hold another agent's work.
- `gem push`, `rake release`, `gem yank`, or create or push a `v*` tag by hand. Release = merge a `lib/zsv/version.rb` bump (`RELEASE.md`, `/release`).
- Bump zsv by hand. Only `rake "zsv:bump[X.Y.Z]"` (it runs `zsv:vendor`), then the full suite, `bin/check asan`, and `rake bench` before and after: skill `upgrade-zsv`. Its PR is `chore: zsv X.Y.Z` and never touches `version.rb`.
- Edit anything under `ext/zsv/vendor/`. A zsv bug goes upstream.
- Make the build download, or add a runtime dependency to the gemspec.
- Run two compiles at once in this checkout (see One compiled artifact).
- Claim a performance number you did not measure, or copy one into docs.
- Hardcode Ruby / OS version lists in docs, README or comments. Point at `ci.yml`.
- Weaken the gate to get green: `rubocop:disable`, `clang-format off`, `-w`, `skip` / `pending`, deleting a failing spec, lowering a GC-stress iteration count, retrying a flaky spec.
- Swallow errors: no blanket `rescue StandardError` that returns `nil` / `[]`; no ignored `enum zsv_status`; zsv must never drop data silently.
- Add compat shims, deprecated aliases, dead-code comments or speculative abstractions.
- Merge a breaking change (removed or renamed method or option, changed default, different rows for an input that parsed before, a raised Ruby floor) without the owner's decision.

## Commands

| Task | Command |
|---|---|
| Install | `bin/setup`: the Ruby in `.ruby-version` (mise, else rbenv), gems, `rake compile`. Idempotent, offline after the gems |
| Pre-PR gate | `bin/check`: repo guards + rubocop + clang-format + compile + full rspec. CI's `check` job runs this script unchanged |
| Inner loop | `bin/check fast`: lint on files changed vs `origin/main` + incremental compile + specs not tagged `:slow` |
| Named files | `bin/check files <paths>`: rubocop on the Ruby ones, clang-format on `ext/zsv/*.{c,h}`, rspec on the `*_spec.rb` ones. **Never compiles**: the only tier allowed when agents share the checkout |
| Sanitizers | `bin/check asan`: clean rebuild with ASan + UBSan, suite with the runtimes preloaded, then a clean normal rebuild. Linux + gcc; exit 75 elsewhere (CI's `sanitizers` job grades it). Required for every C change |
| Guards only | `bin/repo-guards`: CI ↔ `bin/check` parity, agent-surface scan, size caps, version sync |
| Single spec | `bundle exec rspec spec/zsv_spec.rb:LINE`; rerun failures: `bundle exec rspec --only-failures` |
| Lint fix | `bundle exec rubocop -a <file>`, `clang-format -i ext/zsv/<file>` |
| Console | `bin/console`: IRB with `ZSV` and `CSV` loaded |
| Benchmarks | `bundle exec rake bench` (`benchmark/*_bench.rb`, against `CSV`). Before and after for a hot-path change, a zsv upgrade or any speed claim |
| Clean rebuild | `bundle exec rake clean`, then `bin/check` |
| zsv upstream | `bin/zsv-upstream-check` (exit 0 current, 10 newer release, 1 error) · `bundle exec rake "zsv:bump[X.Y.Z]"` · `rake zsv:vendor` · `rake zsv:check` (offline: tree matches the pin) · `rake zsv:verify` (network: tree = verified tarball) |
| Release | Merge a `lib/zsv/version.rb` bump to `main` (`RELEASE.md`, `/release`) |

**Exit codes:** 0 green. **75 = environment missing (Ruby, gems, a C compiler, the compiled extension, sanitizer runtimes): nothing was graded.** Run `bin/setup` and rerun; never report 75 as a failing change, never as a pass. `GREEN (NOT GRADED: clang-format)`: clang-format is not installed here, CI grades it. Anything else: a check ran and is red; the last lines name the failing command and how to rerun it.

Changed `Gemfile`, the gemspec, `extconf.rb` or `ZSV_UPSTREAM`: `bin/setup` before `bin/check`.

### One compiled artifact

`rake compile` builds one `lib/zsv/zsv.so` (`.bundle` on macOS) through one `tmp/` tree, and every spec loads it. Two compiles at once (`bin/check`, `bin/check fast`, `bin/check asan`, `rake`, `rake compile`, `rake spec`, `rake bench`) corrupt each other and produce failures that look like real bugs. With several agents in the checkout: **`ext/zsv/*.{c,h}` is one slice with one owner, the only one compiling**; everyone else uses `bin/check files`.

## Architecture

| Layer | Path | Owns |
|---|---|---|
| Ruby API | `lib/zsv.rb`, `lib/zsv/` | Module methods, option normalisation and validation, input resolution (path vs data vs IO), error classes, `Enumerable` on the parser. Prepended over the C-defined methods |
| Bindings | `ext/zsv/zsv_ext.c` | `Init_zsv`, `ZSV::Parser` TypedData (mark, free, size, compact), thin `rb_zsv_*` methods |
| Bridge | `ext/zsv/parser.c` | zsv callbacks, sources (file, String, IO), `shift`, `rewind`, release. **The critical file** |
| Rows | `ext/zsv/row.c` | Cell bytes → frozen Ruby Strings → `Array` or `Hash` rows; headers |
| Options | `ext/zsv/options.c` | Options Hash → C struct, range checks |
| Build | `ext/zsv/extconf.rb`, `upstream.rb`, `ZSV_UPSTREAM`, `rakelib/zsv.rake`, `Rakefile` | Vendoring, the static libzsv build, cross-compiled platform gems (`NATIVE_PLATFORMS`) |
| zsv | `ext/zsv/vendor/zsv/` | Upstream's parser. Read-only; API in `include/zsv.h` |

Errors: `ZSV::Error` < `StandardError`; `ZSV::MalformedCSVError`, `ZSV::InvalidEncodingError`. Bad options raise `ArgumentError` before any file is opened.

## Conventions

- Match nearby code. Ruby style is RuboCop (`.rubocop.yml`: single quotes, frozen string literals; `ext/` excluded). C style is `.clang-format` (LLVM base, 4 spaces, 100 columns), applied to our C only.
- Test first. A wrong row → `CSV`'s answer for the same input is the expected value. A crash → reproduce under `GC.stress` or `bin/check asan` first (skill `debug-gc`).
- A new option or method: parity spec against `CSV`, then `docs/API_REFERENCE.md`, `README.md`, `llms.txt`, and a `CHANGELOG.md` line under `## [Unreleased]`.
- Never bump `version.rb` in a feature PR.
- Before a PR that touches `ext/`: agent `c-safety-reviewer`. Verification tiers: skill `verify-change`. Plans: `/planx` → `docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/`; a one-file fix needs none.

## Pull requests

- **`CI OK` is the required check**: the aggregate job of `ci.yml`; every job must pass, skipped or cancelled counts as failed. Live rules: `gh api repos/sebyx07/zsv-ruby/rulesets`.
- **A PR body claims only what the diff does.** Evidence you could not get is stated as missing.
- One concern per PR. Keep it a draft (or `WIP` in the title) until ready: a ready, reviewed, green PR is merged by the bot.
- Fill `.github/PULL_REQUEST_TEMPLATE.md`. `bin/check` green on the tree the PR actually contains.
- Titles that are contracts: `chore: zsv X.Y.Z` (the upgrade), `release: X.Y.Z` (the bump). The scheduled checkups find them by title.

## Release lane

`ZSV::VERSION` follows the zsv pin (invariant 6). Merging a PR that changes it **is** the release: `release.yml` runs the full CI, builds the source gem and the precompiled platform gems, publishes through RubyGems trusted publishing (OIDC, no API key), then tags `v<version>` and creates the GitHub Release from `CHANGELOG.md`. No version bump, no publish. Steps and recovery: `RELEASE.md`; prepare with `/release`.

Following upstream: zsv ships `X.Y.Z` → `chore: zsv X.Y.Z` (skill `upgrade-zsv`; monthly task `.dz/schedules/upstream-zsv.md`) → `release: X.Y.Z` (weekly `release-due`).

## AI-maintained

Run by the developerz.ai maintainer agent; policy in `.dz/` (`README.md`, `maintainer/maintainer.yml`, `maintainer/reviewer.md`, `schedules/`). It triages issues, reviews every PR and **merges on green**, so soak and review happen before the push, not after. Outside changes to `.github/`, `bin/`, the `Rakefile`, the gemspec, `extconf.rb`, the zsv pin or `VERSION` stay with the owner; breaking changes ask the owner first.
