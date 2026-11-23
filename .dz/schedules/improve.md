# Brief: monthly improvement

Fired on the first Thursday of the month (UTC days 1-7, `weeks_of_month: [1]`) by `schedules: improve`
in `.dz/maintainer/maintainer.yml`, after `canary.yml`'s run on the 1st and after that week's
`upstream-zsv` task. It runs as a devops task (`mode: devops`): a shell on a checkout, delivering
one pull request.

zsv-ruby is maintained by agents only. Once a month, leave it measurably better and one step ahead
of the next Ruby release. Read `CLAUDE.md` and `ext/CLAUDE.md` first: their invariants (GC safety,
`zsv_finish` exactly once, parity with CSV for documented options, offline pinned build, gem
version mirrors zsv) bind every change. `bin/setup && bin/check` must be green before any PR; exit
75 means the box is missing something, not that the change failed.

Not this brief's job: upgrading zsv (`.dz/schedules/upstream-zsv.md`), bumping the version
(`.dz/schedules/release-due.md`).

## Rows

- `canary-red`: the latest `canary.yml` run (Ruby head; zsv upstream `main` and latest release) failed, or none ran in the last 35 days (§1).
- `ruby-release`: a Ruby release this gem must support is not covered by CI or the canary, or an end-of-life Ruby is still in the matrix (§2).
- `memory-safety`: the suite under sanitizers or GC stress reports something, or a `ext/CLAUDE.md` rule is broken on `main` (§3).
- `parity-gap`: a documented option gives rows that differ from Ruby's `CSV` for some input (§4).
- `correctness`: an open `bug` issue with a reproduction (§5 item 2).
- `bench-regression`: a benchmark row is more than 10 % slower than last month's, reproduced (§5 item 3).
- `docs-drift`: a claim in `README.md`, `CLAUDE.md`, `llms.txt` or `docs/` no longer matches the code (§5 item 4).
- `dead-code`: dead code, duplicated logic, or a slow or flaky spec (§5 item 5).

## 1. Canary first

`gh run list --workflow canary.yml --limit 1 --json conclusion,url,createdAt`. If it failed, find the
cause in the log (`gh run view <id> --log-failed`).

- Ruby head broke our C (a removed or deprecated C API, a new warning that is an error): fix it here.
- zsv upstream `main` broke the build or the suite: that is a preview of the next zsv release. Do not
  work around it with shims; if no open issue names it, file `zsv main breaks zsv-ruby: <summary>` with
  the log, and report it upstream at `liquidaty/zsv` when the regression is theirs.
- No run younger than 7 days: start one (`gh workflow run canary.yml`) and read it before §5.

## 2. Ruby releases

`https://www.ruby-lang.org/en/downloads/releases/` and `https://www.ruby-lang.org/en/downloads/branches/`
against the matrix in `.github/workflows/ci.yml`, `.ruby-version` and `required_ruby_version` in
`zsv.gemspec`. A new stable Ruby goes into the matrix and `.ruby-version` moves to the newest patch
(`bin/setup && bin/check` after). An end-of-life Ruby leaves the matrix; raising the gemspec floor
is breaking and escalates. Never copy the list into docs.

## 3. Memory safety sweep

```bash
bin/check asan                      # the suite under ASan + UBSan, then restores the normal build (Linux; exit 75 elsewhere)
git grep -n 'GC.stress\|GC.compact\|GC.verify_compaction_references' spec/ | head
```

Then read `ext/zsv/*.c` against `ext/CLAUDE.md` once, line by line, as the `c-safety-reviewer`
agent would (`.claude/agents/c-safety-reviewer.md`): unmarked `VALUE`s, allocation reachable from
free, a raise that leaks a `FILE *` or a `zsv_parser`, a second `zsv_finish` / `zsv_delete`, a cell
pointer kept past its callback. Every finding needs the line and the triggering call sequence; fix
it with a spec that fails first (under `GC.stress` for lifetime bugs). A public entry point with no
GC-stress spec is a gap worth closing even with no finding.

## 4. Parity with CSV

For each option `docs/API_REFERENCE.md` lists as compatible, the parity specs compare `ZSV` rows
with `CSV`'s for the same input. Extend the inputs where they are thin: empty fields, quoted
delimiters and newlines, escaped quotes, CRLF and lone CR, a BOM, ragged rows, duplicate and empty
headers, no trailing newline, an empty file, a field larger than the read buffer. A difference is
a bug to fix, or a documented difference to add to `docs/API_REFERENCE.md` and `llms.txt` when it
is zsv's by design. Never "fix" parity by patching the vendored tree.

## 5. Pick at most three improvements, in this order

1. Anything the canary, §2, §3 or §4 found.
2. Correctness and safety: open issues labelled `bug` with a reproduction. Every fix comes with a spec.
3. Performance: `bundle exec rake bench` on `main`, compared with the last `benchmark.yml` run on
   `main` (`gh run list --workflow benchmark.yml --branch main --limit 2`). A row more than 10 %
   slower, reproduced twice, is a regression to bisect. An optimisation ships only with before and
   after numbers from the same machine in the PR body.
4. Docs drift: every claim in `README.md`, `CLAUDE.md`, `ext/CLAUDE.md`, `llms.txt` and `docs/`
   still matches the code: method names and signatures, option names and defaults, error classes,
   the zsv version, commands. README carries no speedup number that the latest benchmark run does
   not show.
5. Simplification: dead code, duplicated logic, slow or flaky specs.

## 6. Ship

This run delivers one pull request: the highest-ranked improvement, small and reviewable, titled
with what it changes. File each of the others (two at most) as its own ask, with the evidence. The
body gives the evidence: the failing canary log, the sanitizer report, the input whose rows differ,
the benchmark tables, or the spec that failed before. User-visible changes get a CHANGELOG
`## [Unreleased]` entry. Never bump the version or the zsv pin here; a breaking change escalates to
the owner instead of merging.

A change under `.github/` (a matrix row, a new job or step, a workflow) never shares a pull request
with code. Open it on its own and say in the body that it changes CI: the platform's merge gate
proves only an action pinned to a commit SHA or a narrowed permission on the agent's own pull
requests, and holds every other workflow edit for the owner. Never edit `.dz/maintainer/` here.

If nothing is worth changing this month, do nothing: no empty PRs, no churn.
