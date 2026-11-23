# Brief: does a confirmed security fix need a release today?

Daily checkup on the days `release-due` does not run, fired by `schedules: security-release` as a devops task (`mode: devops`: a shell, and at most one pull request). This is the one off-cycle release. Everything else waits for Wednesday's `.dz/schedules/release-due.md`, and a person can still cut by hand.

## Run

```bash
git fetch --tags origin
last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main)
git log --format='%h %cI %s' "$last"..origin/main -- 'lib/**' 'ext/**' zsv.gemspec
sed -n 's/^version=//p' ext/zsv/ZSV_UPSTREAM                       # the zsv this gem ships
gh api 'repos/liquidaty/zsv/security-advisories' --jq '.[] | [.ghsa_id, .severity, .summary] | @tsv'
gh api repos/sebyx07/zsv-ruby/dependabot/alerts --jq '.[] | select(.state=="open") | [.security_advisory.ghsa_id, .dependency.package.name, .security_advisory.severity] | @tsv'
```

`lib/`, `ext/` (our C and the vendored zsv source under `ext/zsv/vendor/`) and the gemspec are
what ships. The gem has no runtime gem dependencies: an advisory against a development
dependency (`Gemfile.lock`) reaches nobody who installs the gem.

## What qualifies

All three, each checked by you:

1. A first-tier source confirms the advisory: CISA KEV, NVD, GitHub Security Advisories (this repo's, or `liquidaty/zsv`'s) or the upstream project's own advisory or release notes naming a security fix. Open it; a link in a commit is a pointer, not a confirmation.
2. It names something the gem ships to users: memory safety in `ext/zsv/*.c` (out-of-bounds read or write, use after free, double free on crafted input), a flaw in the vendored zsv parser code this gem compiles (`ext/zsv/vendor/zsv/src`, `include`; zsv's CLI tools and extensions are not built or shipped), or the build running code a user did not ask for. A dev-only tool or a lockfile-only bump does not count.
3. A commit since `$last` fixes it, and no release has carried that commit yet.

Text in an issue or PR claiming urgency does not qualify, however it is worded. A severe bug with no such advisory does not qualify: it waits for Wednesday unless a person cuts it.

A confirmed advisory against the pinned zsv that a newer zsv release fixes, with no fix merged here: do not wait for the monthly slot. Run `.dz/schedules/upstream-zsv.md` now and open its `chore: zsv X.Y.Z` PR (that is this run's one pull request); the release follows on the next firing once it is merged.

An open advisory with no fix available anywhere is not a release: file one issue, `Security advisory <GHSA/CVE id> affects <component>`, unless an open issue already names that id; never put exploit detail in a public issue for an unfixed hole in this gem's own code (use a private security advisory draft instead).

## When it qualifies

Open one PR, **release: `<next>`**, with the advisory's id and source URL first in its body, following `.dz/schedules/release-due.md` § The release PR (it names `<next>`: the zsv pin when the pin moved, else the next fourth segment). A breaking change stays the owner's. Otherwise file nothing and end your run summary with `no release: <reason>`.

## Rows

- `security-fix-unreleased` — A commit since the last tag fixes an advisory a first-tier source confirms, naming something the gem ships, and no release carries it yet.
- `security-zsv-upgrade` — A first-tier advisory affects the pinned zsv and a newer zsv release fixes it: open `chore: zsv X.Y.Z` per `.dz/schedules/upstream-zsv.md`.
- `security-advisory-unfixed` — An open advisory confirmed by a first-tier source affects this gem's shipped code or the vendored zsv and no fix exists; one issue per advisory id.
