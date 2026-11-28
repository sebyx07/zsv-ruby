## Symptom

The scheduled check asks whether a confirmed security fix needs an off-cycle release, an upstream upgrade, or an issue. No specific advisory was supplied.

## Evidence

GitHub's latest gem release is `v1.4.4`, published on 2026-11-23. The public comparison from that tag to `main` reports six commits, through `7a414fcfeff9`, with no changes to `lib/`, `ext/`, or `zsv.gemspec`. The first commit after the release changes development tooling and documentation, not shipped code. The pin is `1.4.4` and GitHub reports upstream's latest full release as `v1.4.4`.

The public GitHub advisory endpoints for [the gem](https://api.github.com/repos/sebyx07/zsv-ruby/security-advisories) and [upstream](https://api.github.com/repos/liquidaty/zsv/security-advisories) both returned `[]`. The GitHub reader supplied to this run does not expose Dependabot alerts or private advisories. Those sources were not checked, so the security assessment is incomplete.

## Root cause

No qualifying unreleased shipping fix was found in the public release comparison, and no public repository advisory was returned. This is not proof that no applicable private advisory or Dependabot alert exists. No product failure was reported or reproduced.

## Fix

No product, release, or upstream pin change was made. The missing authenticated alert and advisory read capability is recorded as blocked. Tests were not run because no executable code changed.

## Verify

Check the public comparison at https://api.github.com/repos/sebyx07/zsv-ruby/compare/v1.4.4...7a414fcfeff9 for changes under `lib/`, `ext/`, or `zsv.gemspec`; at the observed head it shows none. A complete check also requires an authorized reader for open Dependabot alerts and private repository advisories.

no release: no qualifying fix was found in the available evidence; authenticated security alerts were not accessible.
