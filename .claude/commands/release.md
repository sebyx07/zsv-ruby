---
description: Prepare a zsv-ruby release pull request — set version.rb to the version the zsv pin dictates, move CHANGELOG Unreleased into a dated section, verify, open the PR. Merging that PR publishes the gem through CI. Use for release, publish, ship a version, bump the gem version.
argument-hint: [auto|X.Y.Z|X.Y.Z.N]
---

# /release

**Merging a version bump into `main` is the publish action.** `.github/workflows/release.yml` sees the new `ZSV::VERSION`, verifies, publishes to RubyGems with OIDC trusted publishing (no API key anywhere), then tags and creates the GitHub release. Your job ends at an open, green release PR — plus the merge when the user asked for it.

`RELEASE.md` is the source of truth for the pipeline; read it first, and follow it where it differs from this file.

## Target version
$ARGUMENTS (default `auto`)

The gem version mirrors the wrapped zsv C library, so it is derived, not chosen:

```bash
pin=$(sed -n 's/^version=//p' ext/zsv/ZSV_UPSTREAM)
cur=$(ruby -r ./lib/zsv/version -e 'print ZSV::VERSION')
```

| State | Version |
|---|---|
| `$pin` is ahead of `$cur` (a `chore: zsv X.Y.Z` merged) | `$pin` |
| `$pin` equals the first three segments of `$cur` | gem-only release: next fourth segment (`1.4.4` → `1.4.4.1` → `1.4.4.2`) |
| an argument that fits neither row | stop and say why: `bin/repo-guards` rejects a gem version ahead of the pin |

Want a newer zsv? That is skill `upgrade-zsv` and its own PR, merged before this one. A breaking gem-only change (removed method or option, changed default, different rows) needs the owner's explicit go-ahead.

## Steps

1. **Preflight** — any failure → stop and report.
   - `git fetch origin && git status --short` clean, on an up-to-date `main`
   - `gh run list --branch main --workflow ci.yml --limit 1` is green
   - no `chore: zsv …` PR is open (`gh pr list --search 'chore: zsv in:title' --state open`): it ships first
   - `## [Unreleased]` in `CHANGELOG.md` is non-empty; empty → draft entries from `git log v$cur..HEAD -- lib ext zsv.gemspec` and get approval
   - the version is unused: `git tag -l vX.Y.Z` prints nothing and `gem list -r zsv --all` does not list it
2. **Branch:** `git checkout -b release/X.Y.Z`. No other release PR may be open: `gh pr list --search 'release: in:title' --state open` prints nothing.
3. **Bump:**
   - `lib/zsv/version.rb` → `VERSION = 'X.Y.Z'`
   - `CHANGELOG.md` → rename the filled `## [Unreleased]` to `## [X.Y.Z] - <date +%F>`, drop its empty subsections, add a fresh empty `## [Unreleased]` above it
   - every other mention of the old version: `git grep -n -F "$cur" -- ':!CHANGELOG.md' ':!ext/zsv/vendor'`
4. **Verify:** `bin/check` green; `bundle exec rake zsv:verify` (the vendored tree is the pinned tarball); `gem build zsv.gemspec` builds without warnings, then delete the built `.gem` file.
5. **PR:** one commit `release: X.Y.Z` containing only the bump. `git push -u origin HEAD`, then `gh pr create --title "release: X.Y.Z"` with the new changelog section as the body. The title is a contract: the `release-due` checkup finds an open release PR by it. `gh pr checks --watch`.
6. **Merge** only on green and only when the user asked for the release to go out: `gh pr merge --squash --delete-branch`. Then watch the publish: `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`.
7. **Confirm:** `gem list -r zsv` shows X.Y.Z and `gh release view vX.Y.Z` exists. Report both, or report exactly which job of `release.yml` failed and apply `RELEASE.md`'s recovery section:
   - failed before the gem was pushed: fix on `main`, keep the same version
   - the gem is on RubyGems but the tag or GitHub release is missing: re-run the workflow on `main` before any other version bump merges
   - the published gem is broken: tell the user; the owner yanks it, and the fix ships as the next fourth-segment version

## Never

- Never `gem push`, never `rake release` (the task aborts on purpose), never `gem yank` (yanking is the owner's call).
- Never create or push a `v*` tag — `release.yml` owns tagging.
- Never reuse a version number that reached RubyGems. A version that never got there keeps its number.
- Never change `ext/zsv/ZSV_UPSTREAM` or mix feature work into the release PR.
