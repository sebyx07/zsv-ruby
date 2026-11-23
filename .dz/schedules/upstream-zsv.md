# Brief: follow upstream zsv

Monthly, the first Monday (UTC days 1-7) at 05:00 UTC, fired by `schedules: upstream-zsv` in `.dz/maintainer/maintainer.yml` as a devops task (`mode: devops`: a shell on a checkout, at most one pull request). Also run on demand by `.dz/schedules/security-release.md`.

zsv-ruby wraps the zsv C library (`liquidaty/zsv`) and **gem X.Y.Z ships zsv X.Y.Z**. The source is vendored at `ext/zsv/vendor/zsv` and pinned (version + tarball SHA-256) in `ext/zsv/ZSV_UPSTREAM`. This task keeps the pin on upstream's latest release. It never bumps `lib/zsv/version.rb`: the weekly `release-due` checkup cuts gem X.Y.Z after this PR merges. Read `CLAUDE.md`, `ext/CLAUDE.md` and skill `upgrade-zsv` first.

## 1. Is there a newer release?

```bash
bin/setup                 # exit 75 = the box lacks Ruby or a C compiler: stop, row upstream-check-failed
bin/zsv-upstream-check; rc=$?
old=$(sed -n 's/^version=//p' ext/zsv/ZSV_UPSTREAM)
new=$(gh api repos/liquidaty/zsv/releases/latest --jq .tag_name | sed 's/^v//')
```

| `rc` | Means | Do |
|---|---|---|
| 0 | the pin is upstream's latest release | stop: `no upgrade: zsv <old> is current` |
| 10 | upstream has a newer release | continue; `$new` must agree with what the script printed |
| other | the check itself failed (network, GitHub API, rate limit) | retry once after a minute; still failing → row `upstream-check-failed`, change nothing |

Only upstream's latest full release counts: never a prerelease, a draft, a branch or `main` (the canary builds those). Several releases behind → go straight to `$new`; gem versions may skip.

Stop without a PR when either is true, and say which:

- `gh pr list --search 'chore: zsv in:title' --state open` prints a PR: one upgrade in flight at a time. If it is red or stale, fix it there.
- `gh issue list --state open --search '"zsv '"$new"' upgrade" in:title'` prints an issue: the owner has it.

## 2. Read what changed, before touching anything

```bash
gh release view "v$new" -R liquidaty/zsv --json body,publishedAt,url
gh api "repos/liquidaty/zsv/compare/v$old...v$new" --jq '.files[] | select(.filename | test("^(include|src)/|^configure$|^LICENSE$")) | [.status, .filename] | @tsv'
grep -ohE '\bzsv_[a-z0-9_]+' ext/zsv/*.c ext/zsv/*.h | sort -u      # the zsv API this gem calls
```

Read every intermediate release's notes too (`gh release list -R liquidaty/zsv --limit 20`). For each symbol in the last list, read its declaration and doc comment in `include/` at both tags, and the diff of `struct zsv_opts`.

**Breaking, the owner's (§6), when any holds:**

- a function, struct field or enum value this gem uses is removed, or changes meaning in a way a mechanical edit cannot absorb (a rename or an added parameter with an obvious value is mechanical);
- upstream documents changed parse results (quoting, BOM, line endings, delimiters, a changed default) and a spec here confirms rows differ for input that parsed before;
- `LICENSE` changed; the library build needs the network, a new system library, or a newer C standard or compiler than CI has;
- upstream marks the release as breaking or as a new major.

## 3. Baseline on fresh `main`

```bash
git fetch origin && git checkout -B chore/zsv-"$new" origin/main
bin/check                                   # must be green before the bump, or stop: row main-not-green
bundle exec rake bench 2>&1 | tee tmp/bench-before.txt
```

## 4. Bump and re-vendor

```bash
bundle exec rake "zsv:bump[$new]"     # rewrites ZSV_UPSTREAM (version + sha256), re-vendors ext/zsv/vendor/zsv
curl -fsSL "https://github.com/liquidaty/zsv/archive/refs/tags/v$new.tar.gz" | sha256sum   # must equal sha256= in ZSV_UPSTREAM
bundle exec rake zsv:verify           # the tree is byte-identical to the verified tarball
bundle exec rake zsv:vendor && git status --short ext/zsv/vendor   # idempotent: no further change
```

Never edit a file under `ext/zsv/vendor/` and never type a hash by hand. A hash that differs between the two downloads is not a retry: stop, row `upstream-check-failed`, and say so (a moved tag is a supply-chain event).

## 5. Prove it

```bash
bundle exec rake clean && bin/check   # full gate on a clean build: guards, lint, compile, the whole suite
bin/check asan                        # the suite under AddressSanitizer + UBSan, then restores the normal build (Linux; exit 75 elsewhere: CI's sanitizer job grades it)
bundle exec rake bench 2>&1 | tee tmp/bench-after.txt
```

- Compile errors or new warnings in `ext/zsv/*.c`: adapt our C when the change is mechanical (§2), with a spec for anything behavioural. Our C only; the fix is never a patch to the vendored tree.
- A failing parity spec means upstream changed parse results: that is §6, not a spec to rewrite.
- Any sanitizer report is a blocker: fix it when it is in our C; when it is inside zsv, §6 with the report, and an upstream issue.
- Benchmarks: compare every row of before and after, twice if a row moves more than 10 %. A reproduced slowdown over 10 % does not ship silently: §6.

## 6. Breaking or unprovable → an issue, not a PR

File one issue titled `zsv <new> upgrade needs the owner: <summary>` (skip if one is open) with: the upstream release URL, the compare URL, which rule of §2 or §5 fired, the failing output (spec diff, sanitizer report, both benchmark tables), and what a fix would take. Push nothing. End the run with `no upgrade PR: <reason>`.

## 7. Ship one PR

- `CHANGELOG.md`, under `## [Unreleased]` → `### Changed`: `Upgraded the vendored zsv C library from <old> to <new>` with the upstream release link, plus one line per change a user of this gem can observe.
- `git grep -n -F "$old" -- ':!CHANGELOG.md' ':!ext/zsv/vendor'`: fix docs that name the zsv version (not `lib/zsv/version.rb`).
- Commit only: `ext/zsv/ZSV_UPSTREAM`, `ext/zsv/vendor/zsv/**`, `CHANGELOG.md`, the docs lines, and our C + specs if §5 needed them. Stage by path. Nothing under `.github/`, `.dz/`, `bin/`.
- Title exactly `chore: zsv <new>` (the `release-due` and `health` checkups find it by that title). Body: upstream release and compare URLs; the SHA-256 and that both downloads matched; the list of zsv symbols this gem uses whose declaration changed, or "none"; `bin/check` and `bin/check asan` results; the before and after benchmark tables with Ruby version and CPU; what you could not verify, stated as missing.

It merges on green (`CI OK`) like any PR. Do not open a release PR here.

## Rows

- `upstream-newer` — upstream's latest zsv release is newer than the pin and passes §2 and §5: one PR, `chore: zsv <new>`.
- `upstream-breaking` — the newer release is breaking (§2), or fails the suite, the sanitizers or the benchmarks in a way our C cannot absorb (§5): one issue for the owner, no PR.
- `upstream-check-failed` — `bin/zsv-upstream-check` or `bin/setup` could not run, or the tarball hash did not reproduce: nothing changed; say what failed.
- `main-not-green` — `bin/check` is red on `main` before the bump: no upgrade on top of a red tree; say what is failing.
