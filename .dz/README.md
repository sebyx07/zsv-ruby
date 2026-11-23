# `.dz/`

Repo-scoped configuration for the [developerz.ai](https://developerz.ai) maintainer agent, which runs
this repository as an AI-managed project.

- `maintainer/maintainer.yml`: the maintainer policy (triage, PRs, review, releases, schedules).
- `maintainer/reviewer.md`: this repo's layer of the reviewer prompt (C safety first; what to reject, what never to flag).
- `pipeline/agent-pipeline.json`: the agent pipeline definition.
- `schedules/`: the scheduled briefs the policy fires: `health` (daily), `release-due` (weekly),
  `security-release` (the other days), `upstream-zsv` (monthly: follow the wrapped zsv C library),
  `improve` (monthly).
- `onboarding/scorecard.md`: the AI-first scorecard; each onboarding run rewrites it.

The gem version mirrors the wrapped zsv release (gem X.Y.Z wraps zsv X.Y.Z). `upstream-zsv` opens
`chore: zsv X.Y.Z` when upstream ships; `release-due` then opens `release: X.Y.Z`. Releasing is
merging a `lib/zsv/version.rb` bump to `main`: `release.yml` publishes the gem through RubyGems
trusted publishing, then tags it. Nobody tags or `gem push`es by hand.

Agent instructions for working on the code live in `CLAUDE.md`. The gate is `bin/check` locally and
the `CI OK` check on GitHub.
Docs: https://developerz.ai/docs/maintainer-yml
