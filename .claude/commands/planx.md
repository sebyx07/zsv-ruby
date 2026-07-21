---
description: Write a concise, self-contained multi-file execution plan to docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/ for another AI to implement.
argument-hint: [what you want done]
allowed-tools: Write, Read, Glob, Grep, Bash, Agent
---

# /planx

Produce a plan another AI can execute with zero extra context. Plan only — no implementation, no compiling, no edits outside the plan dir.

## Goal
$ARGUMENTS

## Steps

1. **Resolve path.** `date +%Y`, `date +%m`, `date +%d`. Dir = `docs/plans/<YYYY>/<MM>/<DD>/`. Next number = highest existing `1NN-*` + 1, else `101`. Slug = kebab-case, ≤5 words. Plan dir: `docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/`.

2. **Explore.** Files to touch (`file:line`): `ext/zsv/{zsv_ext,parser,row,options}.c/h`, `common.h`, `extconf.rb`, the Ruby surface under `lib/`, specs in `spec/zsv_spec.rb`, benchmarks in `benchmark/`. Executors work in this checkout — no worktrees, no second clone (vendor/zsv is downloaded at compile time and lives here once).

3. **Write the plan as multiple files** — never one big `plan.md`. Always `overview.md` plus one `<NN>-<aspect>.md` per separable area (e.g. `01-parser-bridge.md`, `02-row-building.md`, `03-ruby-api.md`, `04-specs.md`, `05-bench.md`).

   **`overview.md`** — Goal (1-2 sentences) · Context (Ruby C extension over zsv 1.4.3, callback→pull bridge with row buffering, RSpec, RuboCop clean) with reference patterns as `file:line` · Plan files in execution order · Done when (incl. `bundle exec rake` green, `rubocop` 0 offenses).

   **Each `<NN>-<aspect>.md`** — Files to change (`path:line`) · Steps (ordered, concrete) · Tests (`bundle exec rspec spec/zsv_spec.rb:<line>`) · Done when.

4. **Write a `status.yml`** in the plan dir: `plan`, `title`, `status` (not_started | in_progress | blocked | complete | superseded), `created_by`/`owner` from `git config user.name`, `worked_by: ""`, `percent`, `current_focus`, `slices` (status + percent each), `evidence: []`, `notes`, `last_updated`. Valid YAML — the only tracker; slices stay reference maps.

## Rules
- Compact English. Fragments. `file:line` and `func()` refs over prose. No checkboxes. Point at code, don't paste it.
- Call out the invariants any slice touches: no Ruby allocation during GC (`in_cleanup`), `zsv_finish()` exactly once, custom-header skip, string-vs-path detection.
- Perf-relevant slices state the benchmark to run and the expected direction.
- Public API change → a slice for `docs/` (QUICKSTART, API_REFERENCE) and the version story (gem version tracks zsv 1.4.3).
- Executors work directly in this checkout — never plan around git worktrees.

## Output
```
✓ docs/plans/<YYYY>/<MM>/<DD>/<1NN>-<slug>/overview.md
  + 01-<aspect>.md, … + status.yml
```
