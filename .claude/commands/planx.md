---
description: Write a concise, self-contained implementation plan to docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/ for another agent to execute. Plan only — no source edits. Use for planx, plan this, design before building.
argument-hint: [the change you want planned]
---

# /planx

Plan only. No implementation, no edits outside the plan dir. The executor reads `overview.md`, its own slice, and the files those cite — nothing else.

Skip it for small work: this gem is about a thousand lines of C and a small `lib/`; a one-file fix does not need a plan dir.

## Goal
$ARGUMENTS

## Steps

1. **Resolve the path.** `date +%Y`, `date +%m`, `date +%d`. `ls -d docs/plans/<YYYY>/<MM>/<DD>/1*` → next number = highest `1NN-*` + 1, else `101`. Slug = kebab-case, max 5 words. Plan dir: `docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/`.

2. **Explore, read-only, in this checkout.** Record everything the executor would otherwise search for, as `file:line | pattern`:
   - which surface the change lands on: the callback→pull bridge (`ext/zsv/parser.c`), row building (`ext/zsv/row.c`), option conversion (`ext/zsv/options.c`), the Ruby bindings and TypedData functions (`ext/zsv/zsv_ext.c`), or the Ruby surface (`lib/zsv.rb`, `lib/zsv/`)
   - the invariants in play (`CLAUDE.md` § Invariants, `ext/CLAUDE.md`): which `VALUE`s the change stores, who marks them, what can raise, where `zsv_finish` runs
   - the zsv API involved: its declaration in `ext/zsv/vendor/zsv/include/` (read-only; never plan an edit there)
   - how Ruby's `CSV` behaves for the same option and input (`ruby -rcsv -e '…'`): that is the expected output
   - specs to mirror in `spec/`, and the benchmark that would show a regression (`benchmark/`)
   - user-facing docs that go stale: `README.md`, `docs/API_REFERENCE.md`, `docs/QUICKSTART.md`, `llms.txt`, `CHANGELOG.md`

3. **Write the plan as multiple files** — never one `plan.md`.

   `overview.md`: **Goal** (1–2 sentences, what + why) · **Context** (only the facts the executor needs + reference patterns at `file:line`) · **Plan files, in execution order**, one-line hook each · **Done when** (verifiable: named specs green, `bin/check` green, `bin/check asan` clean when C changed, benchmark before/after when the hot path changed) · **Risks / open questions**.

   One `<NN>-<aspect>.md` per separable area of work, e.g. `01-c-extension.md`, `02-ruby-api.md`, `03-docs.md`. Each carries: `> Part of overview.md. Depends on: <NN or none>` · **Files to change** (`path:line` — what, why) · **Steps** (ordered, concrete) · **Tests** (what to add, and `bin/check files <paths>`) · **Done when**.

4. **Write `status.yml`** in the plan dir — the only tracker:

```yaml
plan: <1NN>-<slug>
title: <human title>
status: not_started        # not_started | in_progress | blocked | complete | superseded
created_by: <git config user.name>
worked_by: ""              # executor fills with their git user.name
owner: <git config user.name>
percent: 0
current_focus: ""
slices:
  - { file: 01-<aspect>.md, status: not_started, percent: 0 }
evidence: []               # commits / PRs
works: []                  # confirmed only, each with its proof (spec, PR)
tried_failed: []           # approach + exact reason; the next session does not retry these
deviations: []             # what departed from the plan + why
next_step: ""              # exact: file, function, pattern to mirror
last_updated: <YYYY-MM-DD>
```

## Rules

- **Slices are path-disjoint, and `ext/zsv/*.{c,h}` is always one slice.** There is one compiled artifact (`lib/zsv/zsv.so`): two agents editing C cannot each verify their own work.
- Reference, don't restate: `file:line`, function names. Never paste code — it goes stale immediately.
- No checkboxes in the `.md` files. `status.yml` is the only tracker.
- Tests are part of the slice that changes the behaviour, not a trailing slice of their own. A C lifetime change plans a spec that runs under `GC.stress`.
- Never plan a `git worktree` step or an `isolation: worktree` agent — execution happens in this one checkout.
- Never plan a manual release step (releases happen by merging a version bump: `/release`), an edit under `ext/zsv/vendor/`, or a zsv upgrade done by hand (skill `upgrade-zsv`).

## Output
```
✓ docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/overview.md
  + 01-<aspect>.md, 02-<aspect>.md, …
  + status.yml
Next: /feature docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>
```
