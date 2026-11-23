# Standards

How work is done here, and the check that enforces each rule. The rules themselves live in
`CLAUDE.md` (invariants, never, conventions, pull requests), `ext/CLAUDE.md` (the C rules) and
`spec/CLAUDE.md` (the suite); this page is the map from rule to guard.

| Rule | Enforced by |
|---|---|
| Repo guards, Ruby lint, C format, compile, full suite | `bin/check`, and `CI OK` in CI |
| Ruby style | RuboCop (`.rubocop.yml`) |
| C style, our C only | clang-format (`.clang-format`); CI always grades it |
| No memory error or undefined behaviour in the suite | `bin/check asan`, CI's `sanitizers` job |
| Stored objects survive GC and compaction; no leak on any exit path | GC-stress specs in `spec/`, agent `c-safety-reviewer`, the reviewer |
| Rows equal Ruby's `CSV` for documented options | `spec/api/csv_compat_spec.rb` |
| Every supported Ruby, OS and architecture | CI's `test` matrix |
| The gem installs offline and loads | CI's `package` job, `.github/scripts/gem-smoke.rb` |
| The vendored zsv is exactly the pinned tarball | `rake zsv:check` (offline), `rake zsv:verify` (network) |
| Gem version mirrors the zsv pin | `bin/repo-guards` |
| CI runs the same gate as `bin/check` | `bin/repo-guards` |
| Agent-read files carry no HTML comment or invisible character; `CLAUDE.md` under its size cap | `bin/repo-guards` |
| Workflows are valid; actions pinned to a commit SHA, narrow permissions | actionlint and zizmor in CI's `workflows` job |
| No speed claim without a run behind it | the reviewer (`.dz/maintainer/reviewer.md`), `rake bench` |
| One concern per pull request; breaking changes ask the owner | the reviewer, `escalate` in `.dz/maintainer/maintainer.yml` |
