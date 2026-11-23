# Devops checkup

Weekly checkup, Saturdays 05:00 UTC, OFFERED and off: the `devops` entry in
`.dz/maintainer/maintainer.yml` is commented out, and uncommenting it is the opt-in. It is the
developerz.ai platform's standard devops checkup, adapted to zsv-ruby: how this repository ships,
graded on five axes. A read-only scout: you read files only, no shell, network or database. You
also have the Signals block: recent CI job failures and failed tasks.

What ships here: the Ruby gem `zsv`, a C extension with the zsv C library's source vendored inside
it, as one source gem and one precompiled gem per `NATIVE_PLATFORMS` entry in the `Rakefile`.
`.github/workflows/release.yml` publishes them through RubyGems trusted publishing when
`lib/zsv/version.rb` changes on `main`, then tags. There is no server, container, site or database.
The gem version mirrors the vendored zsv version (`ext/zsv/ZSV_UPSTREAM`).

**Evidence or nothing.** Every point lost names a `path:line` or a Signals line. A number you
cannot read is reported as `not read`, never an estimate, and a finding whose harm depends on a
size or a rate you cannot see is marked `measure first: yes`. Do not fix what is not broken.

## The axes

1. **Reliable.** Does a change get proved before it ships, and can a bad one be undone?
   - `bin/check` and CI run the same gate (`ci.yml`'s `check` job runs `bin/check`; the aggregate
     `CI OK` job needs every other job: the Ruby x OS matrix, `sanitizers`, `package`), and
     `release.yml` runs that whole workflow before any `gem push`.
   - Inputs are pinned: Ruby by `.ruby-version`; zsv by version and tarball SHA-256 in
     `ext/zsv/ZSV_UPSTREAM`, with the vendored tree checked against it (`rake zsv:check` before
     `rake build`, `extconf.rb` before compile). `Gemfile.lock` is not committed, as for any gem
     (`.gitignore`): not a finding. The gemspec has no runtime dependency.
   - The packaged gem is proved, not only the checkout: installed with the network disabled, and
     each precompiled gem loaded on its own platform (`native-gems.yml`).
   - A bad release can be undone: `RELEASE.md` § If a release fails says how (the owner yanks, the
     fix is the next version; a published version is never pushed again).
   - Signals: the same CI job or task failure kind recurring. Report the counts as they stand.
2. **Secure.** What could leak, or run that nobody reviewed?
   - A secret, token or RubyGems credential committed to the tree. Quote the key and path, never
     the value. Publishing is OIDC: an API key anywhere is a finding.
   - Third-party actions pinned to a full commit SHA; workflow `permissions` declared and narrow;
     `persist-credentials: false`; no `pull_request_target`. An exception is listed with its
     reason in `.github/zizmor.yml`.
   - Supply chain of the gem itself: anything that fetches at install or compile time, a system
     libzsv linked, a vendored file that differs from the pinned tarball, TLS verification
     switched off anywhere.
   - In our C (`ext/zsv/*.c`): a length used before its range check, a `memcpy` whose size comes
     from an IO's `#read` unchecked, a path not passed through `FilePathValue`. The parser reads
     untrusted input in the user's process.
3. **Fast.** How long does a change wait for its answer?
   - CI that repeats work: serial jobs that could run side by side, the vendored zsv rebuilt where
     an earlier step built it, a matrix row that duplicates another.
   - Superseded CI runs left running (`concurrency`).
4. **Efficient.** What does this repository carry that it does not use?
   - A development dependency nothing requires, two tools doing one job, a file in the gem that a
     user never loads (`spec.files` in `zsv.gemspec`), a part of the vendored zsv tree the build
     never compiles yet ships.
   - A build product committed beside its source (`*.so`, `*.o`, `tmp/`, `pkg/`).
5. **Cheap.** What costs money every day without paying for itself?
   - A scheduled workflow or checkup far more frequent than its result is read (`canary.yml` is
     monthly, `benchmark.yml` runs on each `main` push); a test matrix wider than the Rubies
     between `required_ruby_version` and the newest release; macOS and arm64 runners doing what a
     Linux x86_64 one proves.
   - Workflow artifacts (built gems) kept with no expiry.
   - Money is almost always `measure first: yes`: name what to measure, never a price you did not
     read.

**CI configuration is graded, never filed.** Read workflow files to score the axes, and report what
you find in your answer. Never name a CI configuration file in a handoff, nor a secret-shaped path:
a handoff naming one is refused whole. The build files (`ext/zsv/extconf.rb`, the `Rakefile`, the
gemspec, the zsv pin) are the owner's: a finding there is a handoff the owner reviews, never an
outside change.

## Rows

One per axis; a handoff reports one failing row.

- `reliable`: a change can ship unproved, or cannot be undone
- `secure`: something can leak, or run unreviewed
- `fast`: a change waits on avoidable work
- `efficient`: the repository carries what it does not use
- `cheap`: something costs money every day without paying for itself

## How to judge

- Confirm before you claim: read the file that does the thing, not only a file that mentions it.
- Rank by blast radius: what crashes or leaks in a user's process or poisons an install first,
  money last.
- Skip specs, benchmarks, generated files and the vendored zsv source (reviewed by hash).
- A check that does not apply to this repository is not a failure.
- One handoff per row: every defect on an axis goes in it, worst first.
- A row the daily `health` checkup (`.dz/schedules/health.md`) already filed is scored, not filed
  again.

## Every finding

Besides the checkup rules' fields, each handoff carries these; one over any limit is dropped whole:

- **work**: one sentence naming the defect and the fix, at most 300 characters.
- **why**: a concrete failure scenario, what triggers it and what breaks, at most 300 characters.
- **evidence**: at most 10 lines of at most 280 characters each. One line `path:line: the code` per
  site. The last line starts `measure first:`, `no` with the reason or `yes` with what to measure
  and how.
- **paths**: at most 20 files.
- **anchor**: the row id (`reliable:`, `secure:`, `fast:`, `efficient:` or `cheap:`), then the
  worst file or symbol, at most 120 characters.
- **metric**: the number the fix moves, at most 200 characters.

## Report

First the score, then the findings.

For each axis, `N of 5` or `not read`: 5 means you looked and nothing failed, and each failing check
costs a point. One line per point lost, with its evidence. Then the total, `N of 25`, or `N of M
over K axes read`, with the change since the last checkup when the Signals block names one.

Then the finding list, worst first: every point lost, including the CI configuration ones no handoff
may carry. Name anything you could not cover, and why.
