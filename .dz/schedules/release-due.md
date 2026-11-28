# Brief: is a release needed?

Weekly checkup, Mondays 09:00 UTC, fired by `schedules: release-due` in `.dz/maintainer/maintainer.yml` as a devops task (`mode: devops`: a shell, and at most one pull request). It asks whether a release is needed now. The block below gathers facts and you make the call. A merge or a count never cuts a release, and the owner can still cut by hand.

## The version is not yours to choose

The gem version mirrors the wrapped zsv C library: **gem X.Y.Z ships zsv X.Y.Z**.

| State on `main` | `<next>` |
|---|---|
| the pin in `ext/zsv/ZSV_UPSTREAM` is ahead of `ZSV::VERSION` (a `chore: zsv X.Y.Z` merged) | the pin, `X.Y.Z` |
| the pin equals the first three segments of `ZSV::VERSION`, and gem-only changes are waiting | the fourth segment, next: `X.Y.Z` → `X.Y.Z.1` → `X.Y.Z.2` |

Never a version whose first three segments differ from the pin (`bin/repo-guards` fails it), never a semver bump of your own. Upgrading zsv is `.dz/schedules/upstream-zsv.md`'s job, not this brief's.

## Judge

Read the window's commits, their diffs and `## [Unreleased]` in `CHANGELOG.md`, then ask: does someone using the gem get something from a release now?

- Usually yes: a merged zsv upgrade (always: users get the new parser), a fix they can hit (a crash, a leak, a wrong row, a build failure on a platform), a new option or method.
- Usually no: a run of dev-dependency, CI, spec, benchmark or docs-only changes. With nothing for users, skip the week: no empty release.

Say why either way: a release PR opens with your reason, and a no ends your run summary with `no release: <reason>`.

## Security: the one off-cycle release

A fix for a security advisory that a first-tier source confirms ships right away instead of waiting for Monday: CISA KEV, NVD, GitHub Security Advisories or the upstream project's own advisory. It qualifies only when it is published, rated high or critical (CVSS ≥ 7.0) or KEV-listed, and in code the gem ships; a dev-only, test or CI dependency never does. Nothing fires on the other days: the owner cuts that release, or it ships at the next weekly run.

## Decide

```bash
git fetch --tags origin
last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --format='%h %cI %s' "$last"..origin/main -- 'lib/**' 'ext/**' zsv.gemspec
git show origin/main:lib/zsv/version.rb | grep VERSION
git show origin/main:ext/zsv/ZSV_UPSTREAM | grep '^version='
```

Those paths are what `zsv.gemspec` ships (`lib/`, `ext/` with the vendored zsv source; README, LICENSE and CHANGELOG ride along but change nothing on their own). Specs, benchmarks, CI, `bin/`, `docs/` and `.dz/` ship nothing.

| Window | Do |
|---|---|
| empty | nothing |
| `ZSV::VERSION` already ahead of `$last` | nothing: a release is in flight (`gh run list --workflow release.yml --limit 1`) |
| the oldest shipping commit is under 24 h old | usually nothing: next week's checkup sees it |
| a **breaking** change (a removed or renamed method or option, a changed default, different rows for an input that parsed before, a raised Ruby floor, a dropped platform) | no release PR: it is the owner's. If no open issue says a breaking release is pending, file one, `Breaking release pending: <summary>`, for the owner, with no release steps |
| otherwise | judge it above; when a release is needed, one PR, **release: `<next>`** |

## The release PR, when a release is needed

1. Re-check the window on fresh `main`; still needed, or stop. `gh run list --workflow ci.yml --branch main --event push --limit 1` must be `success`: nothing releases from a red `main`.
2. `## [Unreleased]` empty (a Dependabot-only window)? Add a `### Changed` line per change that ships. Drop empty `###` headings from the released section. A zsv upgrade's line names both versions and links upstream's release notes.
3. Set `VERSION = '<next>'` in `lib/zsv/version.rb`; move `## [Unreleased]` under `## [<next>] - <today>` (keep an empty `## [Unreleased]` above it). `RELEASE.md` is the source of truth for anything else the bump touches; follow it where it differs from this list.
4. `git grep -n -F '<old version>' -- ':!CHANGELOG.md' ':!ext/zsv/vendor'`: fix what must follow the version (never the pin: it is already `<next>`'s base).
5. `bin/setup && bin/check` green (exit 75 = the environment is missing, not a failure: fix the box), then `gem build zsv.gemspec` without warnings; delete the built `.gem`.
6. One PR titled `release: <next>`, nothing else in it. It merges on green (`CI OK`) like any PR.
7. Merging it is the release: `release.yml` sees the version change on `main`, publishes the gem via RubyGems trusted publishing, then creates the `v<next>` tag and the GitHub release. Never tag, never `gem push`, never `rake release` by hand.

Never open a second release PR while one titled `release: …` is open (`gh pr list --search 'release: in:title' --state open`). Never open one while a `chore: zsv …` PR is open: that upgrade ships first, as its own version.

## Rows

- `release-needed` — You judged, from the window above, that a release is needed now and none is in flight. A breaking change files the owner issue instead.
