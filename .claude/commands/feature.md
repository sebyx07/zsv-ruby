---
description: Take one change in zsv-ruby from idea to merged — explore, build test-first, prove it with bin/check (and the sanitizers when C changed), open one pull request, watch CI, merge. Use for feature, implement, build it, ship this, fix and merge, execute a plan dir.
argument-hint: <what you want built or fixed, or a docs/plans/… dir>
---

# /feature — idea to merged

**Done means merged with CI green on `main`.** A green local gate is not done; an open PR is not done. Publishing the gem is a separate act (`/release`). Report what you verified, never what you assume happened.

## Request
$ARGUMENTS

**Read autonomy from the prompt.** "Just ship it" → run start to finish, decide everything, surface decisions in the PR body. A tentative ask → clarify what is genuinely ambiguous and stop before merge. Always stop for a real blocker: a breaking change to the public API or to the rows returned for an existing input, a zsv upgrade (skill `upgrade-zsv`, its own PR), anything touching published releases.

## Steps

1. **Understand.** Restate the goal in one line and name the surface: the callback→pull bridge (`ext/zsv/parser.c`), row building (`row.c`), options (`options.c`), bindings and TypedData (`zsv_ext.c`), or Ruby (`lib/`). A URL or issue is cited → read it first (`gh issue view <n>`). A plan dir is cited → read its `status.yml` first, then `overview.md`, and resume from `next_step`.
2. **Distrust the paperwork.** Check any plan, `status.yml`, `CLAUDE.md` claim or `docs/` page against the code and `git log --oneline -- <path>` before working from it. Say plainly which claims you falsified and fix the doc in the same change.
3. **Reproduce before theorising.** A failing spec first. Suspected GC or lifetime bug → a spec that runs the path under `GC.stress = true`, then `bin/check asan` (skill `debug-gc`). A wrong row → the same input through `CSV` is the expected output. A platform-only CI failure → `gh run view <id> --log-failed`.
4. **Branch.** `git fetch origin && git status --short` (expect clean), then `git checkout -b <type>/<slug>`. Never build on `main`.
5. **Build test-first.** Failing spec, then the code. No abstraction before a consumer. C rules: `ext/CLAUDE.md`. A new option needs a parity spec against `CSV` and rows in `docs/API_REFERENCE.md`, `README.md` and `llms.txt`.
6. **Prove it** — skill `verify-change`:
   - while iterating: `bin/check fast`
   - once, before the PR: `bin/check` (repo guards, rubocop, clang-format, compile, full rspec: the same as CI)
   - touched `ext/zsv/*.{c,h}` → `bin/check asan`, and agent `c-safety-reviewer` over the diff
   - touched the hot path (`parser.c`, `row.c`) or claimed a speedup → `bundle exec rake bench` before and after, both tables in the PR body. Never claim a number you did not measure.
   - exit 75 → the environment is missing, not the change: `bin/setup`, then rerun
   - red is not a pull request: fix the cause, never silence a cop, a warning or a spec.
   Then a fresh-context pass over `git diff main...`: delete debug output, specs of Ruby's own behaviour, checks for impossible cases; rerun the gate.
7. **Changelog.** User-visible change → one line under `## [Unreleased]` in `CHANGELOG.md`. Never bump `lib/zsv/version.rb` or `ext/zsv/ZSV_UPSTREAM` here.
8. **One PR in flight.** `git add <named paths>` (never `-A`), read `git status --short`, commit, `git push -u origin HEAD`, `gh pr create` (fill `.github/PULL_REQUEST_TEMPLATE.md`). Watch it: `gh pr checks --watch`. Red CI → `gh run view --log-failed`, fix, push. Merge with `gh pr merge --squash --delete-branch`, then `git checkout main && git pull` and confirm `gh run list --branch main --limit 1` is green before starting anything else.
9. **Close.** Re-check the original symptom on `main`. Update the plan's `status.yml` (`evidence`, `works`, `status`), close issues the PR did not auto-close.

## Fan-out — one checkout, one compiled artifact, no worktrees

Most tasks here are a single-agent job: say so and do it yourself. Hive only for a broad read-only search, or for work that spans different surfaces (C, `lib/`, `spec/`, docs).

**Never use git worktrees** — no `isolation: worktree`, no `git worktree add`, no second clone. One checkout; the file set is the only lock.

**`rake compile` writes one `lib/zsv/zsv.so` through one `tmp/` tree**, and every spec loads it. Two compiles at once produce a half-written library and failures that look like real bugs. So:

- **`ext/zsv/*.{c,h}` is one slice, held by one agent.** That agent, or the coordinator, is the only one who compiles.
- Everyone else restates and follows:
  - **Exclusive file set**, named in the brief, plus the paths every other live agent holds. Need a file you do not own → stop and report the collision.
  - **No git at all** — no add, commit, branch, checkout, stash, reset. The coordinator owns git and touches it only once every agent has returned.
  - **Checks narrowed to your own files:** `bin/check files <paths>` (it never compiles). Never bare `bin/check`, `bin/check fast`, `bin/check asan`, `rake`, `rake compile`, `rake spec` or `rake bench`.
  - **Evidence first, diagnosis second.** A hypothesis in a brief is labelled unverified; the agent may drop any premise the code contradicts and must say so.
  - **Never "ask me".** A subagent cannot reach the user: decide and flag the assumption, or stop and report with evidence.

The coordinator runs the repo-wide `bin/check` (and `bin/check asan`, the benchmarks) once, at the end. Shared files (`ext/zsv/common.h`, `lib/zsv.rb`, `zsv.gemspec`, `Rakefile`, `CHANGELOG.md`, `README.md`) are a choke point: one owner, or edited last by the coordinator. A new file must match `spec.files` in `zsv.gemspec`, or it does not ship.

## Hard rules

- Never `--force` push to `main`, never `git stash`, never a git worktree.
- Never `gem push`, never create or push a tag, never `rake release` — CI publishes when a version bump merges (`/release`, `RELEASE.md`).
- Never edit `ext/zsv/vendor/`; never change the zsv pin outside skill `upgrade-zsv`.
- Rows are the product: a change to what an existing input parses to needs a spec asserting it, the same answer from `CSV` (or a documented difference), and a CHANGELOG line.

## Output
```
Shipped:   <what changed, one line per slice>
Gate:      bin/check <green|red>   asan <clean|not run: why>   CI on main <green|red|not checked>
Bench:     <before → after, or "hot path untouched">
PR:        #NNN <merged|open>
Deferred:  <n> — <what, and why not now>        [never omit this line]
Falsified: <plan/doc claims that were wrong, now corrected>
```
