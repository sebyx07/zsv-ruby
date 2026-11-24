## Symptom

The scheduled security check asks whether a confirmed security fix requires an off-cycle release, or whether a shipped component has an open advisory. No specific vulnerability was reported in the task.

## Evidence

`git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main` returned `v1.4.4`. `git log --format='%h %cI %s' v1.4.4..origin/main -- 'lib/**' 'ext/**' zsv.gemspec` returned no commits. The local `origin/main` was `0fa27e7`, and the tag resolved to `0a2b7ff`. The runner owns fetches, so this checkout was not refreshed during the run. Authenticated default branch history also returned `0fa27e7` as its latest commit.

The public GitHub advisory endpoints for [upstream](https://api.github.com/repos/liquidaty/zsv/security-advisories) and [this repository](https://api.github.com/repos/sebyx07/zsv-ruby/security-advisories) each returned `[]`. The [latest upstream release](https://api.github.com/repos/liquidaty/zsv/releases/latest) identifies `v1.4.4`, matching `ext/zsv/ZSV_UPSTREAM`. Open repository issues returned none. These public results do not include private advisories or Dependabot alerts.

## Root cause

No qualifying unreleased shipping fix is visible in the checked local release window, and no newer upstream release exists in the public latest-release response. The advisory check is incomplete: this run has no tool for the repository's authenticated Dependabot alerts or private security advisories. No vulnerability or root cause was established.

## Fix

No release or source change was justified by the available evidence. No live system was changed. Authenticated security alert access and runner-refreshed tags are needed to complete the check. Tests were not run because no executable code changed.

## Verify

After refreshing the runner's checkout, resolve the latest reachable release tag and inspect the resulting window:

```sh
release=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main) &&
  git log --format='%h %cI %s' "$release"..origin/main -- 'lib/**' 'ext/**' zsv.gemspec
```

The observed checkout printed nothing for this log. Separately inspect authenticated Dependabot alerts and private advisories; they were not accessible in this run.

no release: no qualifying unreleased security fix was found, and authenticated alert review remains blocked.
