## Symptom

The scheduled check asks whether a confirmed security fix requires an off-cycle release or an advisory affects shipped code. No specific vulnerability was reported.

## Evidence

The authenticated default branch commit list identified `1ffd3079d882` as its head. The public tags API identified `v1.4.4` at `0a2b7ffd0e8d`. Authenticated commit reads show the four intervening commits changed REPORT.md, CLAUDE.md, onboarding and development files, but not `lib/`, `ext/` or `zsv.gemspec`.

The public GitHub advisory endpoints for [this repository](https://api.github.com/repos/sebyx07/zsv-ruby/security-advisories) and [upstream](https://api.github.com/repos/liquidaty/zsv/security-advisories) returned `[]`. The [latest upstream release](https://api.github.com/repos/liquidaty/zsv/releases/latest) is `v1.4.4`, matching `ext/zsv/ZSV_UPSTREAM`. Public advisory results do not include private advisories or Dependabot alerts. The available authenticated GitHub reader does not expose those alerts and no GitHub MCP tools were connected.

## Root cause

No unreleased shipped-code commit was found, and no newer upstream release was shown. No vulnerability was established. The advisory assessment remains incomplete without authenticated Dependabot and private advisory access.

## Fix

No release or source change was justified by the evidence available. No live system was changed. Tests were not run because no executable code changed. The missing security alert access is recorded in `tmp/dz/devops/blocked.json`.

## Verify

With an authorized GitHub security reader, inspect the repository's open Dependabot alerts and private advisories, and compare the current default branch to the latest release. The public [tag list](https://api.github.com/repos/sebyx07/zsv-ruby/tags) and authenticated commit reads in this run showed no shipped-code changes after `v1.4.4`; private alert results remain unknown.

no release: no qualifying unreleased shipped-code fix was found, and authenticated alert review remains blocked.
