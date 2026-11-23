# Repository census

Weekly report, Mondays 17:00 UTC, fired by `schedules: repo-census` in
`.dz/maintainer/maintainer.yml` as a read-only scout. It is the developerz.ai platform's standard
census, adapted to zsv-ruby: how the automated work on this repository went this week against the
week before, and what in the repository makes it fail. You read files only: no shell, network or
database. Your numbers are the Signals block's, and nothing else.

**A report, never a change.** This census files no handoff and asks for no work: what it finds is
its report, for the people who maintain this repository to read and act on.

**Evidence or nothing.** Every number you quote is a Signals line, with both weeks' counts. A
section marked missing is reported `not read`, never an estimate.

## 1. Compare the two weeks

Read the failed tasks of the last 7 days beside the 7 days before that. Each line is
`origin/kind count`; one missing from a week counts 0 there.

- **regressed**: this week is at least 3 more than the week before and at least double it. Only
  these get a cause.
- **rose**: present the week before and higher this week, short of `regressed`.
- **new**: absent the week before, under 3 this week.
- **fell** or **steady**.

## 2. Find the cause

For each `regressed` kind, read the files a failure of that kind runs through. Here that is the
gate and what it reads: `bin/check` and its steps (`bin/repo-guards`, RuboCop with `.rubocop.yml`,
clang-format with `.clang-format`, `rake compile`, RSpec), `bin/setup`, `bin/_dx.sh` and
`.ruby-version`, the build (`ext/zsv/extconf.rb`, `ext/zsv/upstream.rb`, `ext/zsv/ZSV_UPSTREAM`,
`rakelib/zsv.rake`, the `Rakefile`), the specs under `spec/`, and the C or Ruby source the failing
spec names (`ext/zsv/*.c`, `lib/zsv/`). A cause is a `path:line` you read.

Three failures here are not what they look like; report each as what it is:

- **Exit 75 graded nothing.** The environment was missing: no Ruby from `.ruby-version`, no gems,
  no C compiler, no compiled extension, or, for `bin/check asan`, no Linux gcc with the sanitizer
  runtimes. Report it as environment, with `bin/setup` as the remedy, never as a defect in the
  code.
- **Two compiles at once.** There is one compiled artifact (`lib/zsv/zsv.so`, built through
  `tmp/`). Tasks that compiled in one checkout at the same time corrupt each other and fail in ways
  that look like real bugs (`CLAUDE.md` § One compiled artifact). Suspect it when unrelated tasks
  failed together on load or link errors.
- **A spec that fails sometimes** is a memory bug until proven otherwise (`spec/CLAUDE.md` rule 6,
  skill `debug-gc`), not flakiness: name the spec and the C path it drives.

A failure the repository's files cannot cause or fix, such as a machine lost mid-run, a RubyGems or
GitHub outage, or an upstream zsv release that is not vendored here, is reported as that, with no
cause in the repository. Failing CI jobs are evidence for a cause, never a finding alone.

## Rows

The one row this census reports on. It files no handoff for it.

- `task-failure`: a failed-task kind that regressed, with its cause in this repository

## Report

1. Every kind with both weeks' counts and its verdict, worst first.
2. Each regressed kind's cause: one line `path:line: the code` per site, and what it does to each
   run.
3. What you could not read, and why.

Nothing regressed is a result: say so plainly.
