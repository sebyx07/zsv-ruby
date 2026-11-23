## What and why

One or two sentences. Link issues: `Fixes #123`.

## Changes

-

## Evidence

What you ran and what it printed. State what you could not verify as missing.

- `bin/check`:
- `bin/check asan` (required when `ext/zsv/*.c` or `*.h` changed; Linux):
- `bundle exec rake bench` before / after (required for a hot-path change, a zsv upgrade or a speed claim; include Ruby version and CPU):

## Checklist

- [ ] `bin/check` passes (repo guards, RuboCop, clang-format, compile, full RSpec: the gate CI runs)
- [ ] Changed behaviour has specs; a new or changed option has a parity spec against Ruby's `CSV`
- [ ] C change: every stored `VALUE` is marked, nothing allocates or raises on the free path, `zsv_finish` still runs exactly once, and a spec covers the path under `GC.stress`
- [ ] Nothing under `ext/zsv/vendor/` is edited by hand; the zsv pin changes only through `rake zsv:bump` in a `chore: zsv X.Y.Z` pull request
- [ ] `lib/zsv/version.rb` is untouched (a release is its own pull request)
- [ ] `CHANGELOG.md` `## [Unreleased]` updated for user-visible changes
- [ ] `README.md`, `docs/` and `llms.txt` updated if methods, options or behaviour changed

Keep the pull request a draft until it is ready: the maintainer agent merges a ready pull request once CI is green.
