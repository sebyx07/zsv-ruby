---
name: upgrade-zsv
description: Use when upgrading the vendored zsv C library in zsv-ruby — bin/zsv-upstream-check exits 10, a new liquidaty/zsv release, "bump zsv", "upgrade zsv to X.Y.Z", changing ext/zsv/ZSV_UPSTREAM or ext/zsv/vendor, or a canary failure against upstream zsv.
---

# Upgrade zsv

The gem wraps one pinned zsv release: version and tarball SHA-256 in `ext/zsv/ZSV_UPSTREAM`, source vendored at `ext/zsv/vendor/zsv` (only `LICENSE`, `configure`, `include`, `src`; marker `VENDORED_FROM`). **Gem X.Y.Z ships zsv X.Y.Z**, so a zsv upgrade decides the next gem version. The scheduled version of this procedure is `.dz/schedules/upstream-zsv.md`; keep the two in step.

Two PRs, never one: `chore: zsv X.Y.Z` (this skill: the pin, the vendored tree, any adaptation), then `release: X.Y.Z` (`/release`: `lib/zsv/version.rb`).

## Steps

1. **Check.** `bin/zsv-upstream-check` → exit 0 current (stop) · 10 newer release (continue) · other: the check failed, not a verdict. Only upstream's latest full release: never a prerelease, a branch or `main`.
   ```bash
   old=$(sed -n 's/^version=//p' ext/zsv/ZSV_UPSTREAM)
   new=<the version the script printed as latest=>
   ```
2. **Read what changed** before touching anything:
   ```bash
   gh release view "v$new" -R liquidaty/zsv
   gh api "repos/liquidaty/zsv/compare/v$old...v$new" --jq '.files[] | select(.filename | test("^(include|src)/|^configure$|^LICENSE$")) | [.status, .filename] | @tsv'
   grep -ohE '\bzsv_[a-z0-9_]+' ext/zsv/*.c ext/zsv/*.h | sort -u    # the zsv API we call
   ```
   For each symbol we call, and for `struct zsv_opts`: compare the declaration and its comment at both tags. **Stop and ask the owner** (an issue, no PR) when: an API we use is removed or changes meaning beyond a mechanical edit; upstream documents different parse results; `LICENSE` changed; the build needs the network, a new system library or a newer compiler; upstream calls it breaking.
3. **Baseline** on a branch from fresh `main` (`git checkout -b chore/zsv-$new`): `bin/check` green, then `bundle exec rake bench 2>&1 | tee tmp/bench-before.txt`.
4. **Bump and vendor.**
   ```bash
   bundle exec rake "zsv:bump[$new]"   # rewrites ZSV_UPSTREAM (version + sha256) and re-vendors
   curl -fsSL "https://github.com/liquidaty/zsv/archive/refs/tags/v$new.tar.gz" | sha256sum   # must equal sha256= in ZSV_UPSTREAM
   bundle exec rake zsv:verify         # vendored tree is byte-identical to the verified tarball
   ```
   The hash is computed, never typed. Two downloads that disagree → stop: a moved tag is a supply-chain event, report it.
5. **Prove.**
   ```bash
   bundle exec rake clean && bin/check   # the full gate on a clean build
   bin/check asan                        # ASan + UBSan over the suite (Linux), then restores the normal build
   bundle exec rake bench 2>&1 | tee tmp/bench-after.txt
   ```
   - compile error or new warning in our C → adapt `ext/zsv/*.c` when mechanical, with a spec for anything behavioural
   - a failing parity spec = upstream changed parse results → the owner's call, not a spec to rewrite
   - any sanitizer report → blocker (skill `debug-gc`); inside zsv → owner issue + upstream issue
   - a benchmark row more than 10 % slower, reproduced on a second run → does not ship silently: owner issue with both tables
6. **Record.** `CHANGELOG.md` → `## [Unreleased]` → `### Changed`: `Upgraded the vendored zsv C library from <old> to <new>` + upstream release link + each change a user can observe. `git grep -n -F "$old" -- ':!CHANGELOG.md' ':!ext/zsv/vendor'` → fix docs naming the zsv version. Leave `lib/zsv/version.rb` alone.
7. **PR** titled exactly `chore: zsv <new>`. Stage by path: `ext/zsv/ZSV_UPSTREAM`, `ext/zsv/vendor/zsv`, `CHANGELOG.md`, docs, our C + specs if step 5 needed them. Body: upstream release + compare URLs, the SHA-256, changed declarations of symbols we call (or "none"), `bin/check` and `bin/check asan` results, both benchmark tables with Ruby version and CPU, anything not verified stated as missing.
8. After it merges: `/release` (or the weekly `release-due` checkup) opens `release: <new>`.

## Never

- Never edit a file under `ext/zsv/vendor/`. A zsv bug is reported upstream and worked around in our C, with a spec, only if it can be.
- Never bump the pin without `rake zsv:bump` / `rake zsv:vendor`, the full suite, the sanitizers and the before/after benchmarks.
- Never bump `lib/zsv/version.rb` in the same PR, never tag, never `gem push`.
- Never pin a prerelease, a commit or a branch.
- Never make `extconf.rb` download anything: the gem builds offline from the vendored tree.
