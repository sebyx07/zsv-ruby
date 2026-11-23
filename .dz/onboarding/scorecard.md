# AI-first scorecard

> Hand-written for the AI-maintenance onboarding pass of 2026-11-22, describing the repository as
> it stands once that pass's pull request merges. The next developerz.ai onboarding run rewrites
> this file whole; the latest run wins, and the same card is stored on the platform.

- Computed: 2026-11-22
- Proof: **not yet proved**: written before the pass merged; items marked *pending* depend on
  CI running on GitHub and must be re-checked at head.

## `policy` — ok

- .dz/maintainer/maintainer.yml established (validates against maintainer.v1.json; passes `dz-contract`)
- .dz/maintainer/reviewer.md established (C safety first)
- .dz/schedules/{health,release-due,security-release,upstream-zsv,improve}.md established
- platform-standard briefs: repo-census and repo-score scheduled; hygiene, devops and fix-sweep offered (entries commented)
- .dz/pipeline/agent-pipeline.json established

## `brain` — ok

- CLAUDE.md rewritten (under 12,000 characters, enforced by bin/repo-guards); AGENTS.md is a symlink to it
- nested: ext/CLAUDE.md (C rules), spec/CLAUDE.md, .github/CLAUDE.md

## `roster` — ok

- .claude/agents/c-safety-reviewer.md

## `skills` — ok

- .claude/skills/{verify-change,upgrade-zsv,debug-gc}/SKILL.md

## `commands` — ok

- .claude/commands/{planx,feature,release,bug-sweep}.md; `/release` prepares a version-bump PR, never a tag

## `scripts` — ok

- bin/setup, bin/check (`fast`, `files`, `asan`; exit 75 when the environment is missing), bin/repo-guards, bin/console, bin/zsv-upstream-check (exit 10 when upstream is newer)

## `wiring` — ok

- .mcp.json (codegraph)

## `access` — ok

- no secrets needed: RubyGems publishing is OIDC trusted publishing (no API key)

## `layout` — ok

- single gem at the root; the vendored zsv source under ext/zsv/vendor/zsv is pinned by SHA-256

## `smoke_test` — ok

- spec/ runs against the compiled extension; CI builds the gem and installs it without Bundler

## `env_example` — ok

- no environment variables are needed to build or test

## `agents_md` — ok

- AGENTS.md (symlink), llms.txt

## `per_workspace_brains` — ok

- single-package repository

## `docs_readme` — ok

- docs/README.md indexes docs/idea/ (overview, principles, stack, data-model, deployment, direction draft) and docs/standards/
- docs/ (API_REFERENCE.md, QUICKSTART.md) linked from README.md and llms.txt

## `gate_proved` — pending

- `CI OK` aggregate job, canary.yml, benchmark.yml, dependabot.yml and the version-bump-triggered
  release.yml land in this pass; the ruleset requiring `CI OK` and the RubyGems trusted publisher
  are set by the owner (see the pass's pull request)
