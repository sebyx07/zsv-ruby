# .github/ — CI, canary, release

Outside contributors do not change `.github/`, `bin/`, the `Rakefile`, the gemspec, `ext/zsv/extconf.rb`, the zsv pin or `ZSV::VERSION` (owner only; dependency-bot bumps exempt): `.dz/maintainer/maintainer.yml`.

## Workflows

| File | Trigger | Does |
|---|---|---|
| `workflows/ci.yml` | pull request, push to `main`, manual, `workflow_call` from `release.yml` | The gate. Ends in the aggregate job **`CI OK`** |
| `workflows/canary.yml` | monthly cron (the 1st), manual | Ruby head; zsv upstream's latest release and `main` vendored in place of the pin (`scripts/vendor-zsv-ref.sh`), also under ASan + UBSan; the precompiled gems. **Not** part of `CI OK`; the monthly `upstream-zsv` and `improve` tasks read it |
| `workflows/benchmark.yml` | push to `main` that changes `ext/`, `lib/` or `benchmark/`, manual | `rake bench` on x86_64 and arm64 Linux; output goes to the run's job summary. Not gating. Numbers live there, never in docs |
| `workflows/native-gems.yml` | `workflow_call` from `release.yml` and `canary.yml`, manual | The source gem and one precompiled gem per `NATIVE_PLATFORMS` entry in the `Rakefile` (rake-compiler-dock), each installed and smoke-tested on its own platform and every supported Ruby |
| `workflows/release.yml` | push to `main` touching `lib/zsv/version.rb`, manual on `main` | Verify, build, publish, tag, GitHub Release |
| `dependabot.yml` | weekly | Grouped bundler and actions updates with a 14-day cooldown. The maintainer agent is the only merger; there is no auto-merge workflow. zsv itself is not a Dependabot ecosystem: `upstream-zsv` follows it |
| `zizmor.yml` | - | Reviewed exceptions for the workflow security linter |
| `scripts/` | called by the workflows | `changelog-notes.sh <version>` (that version's CHANGELOG section; fails when missing or empty), `gem-smoke.rb`, `vendor-zsv-ref.sh` |

## `ci.yml` jobs

| Job | Checks |
|---|---|
| `changes` | Reads the changed files: `code=false` when every one is `*.md` or under `docs/`. `check`, `test`, `sanitizers` and `package` then skip; anything unreadable counts as code |
| `workflows` | actionlint + zizmor on `.github/workflows`; `bin/repo-guards` |
| `check` | **`bin/check`**, unchanged, on `.ruby-version` and Linux x86_64 with `ZSV_REQUIRE_CLANG_FORMAT=1`: repo guards, RuboCop, clang-format, compile, RSpec. The only place lint runs |
| `test` | compile + RSpec on every supported Ruby x OS/arch (x86_64 and arm64, Linux and macOS) on a push to `main` that is not docs-only, a manual run and a release; a pull request runs the floor and the newest Ruby on Linux x86_64 + arm64 |
| `sanitizers` | the extension built with `-fsanitize=address,undefined`, the suite with the runtimes preloaded. `bin/check asan` is the same recipe |
| `package` | `rake build`, install the gem into an empty `GEM_HOME` with the network disabled, require it, parse |
| `ci-ok` (`CI OK`) | Fails unless every job above succeeded; cancelled counts as failed, and so does skipped unless `changes` said docs-only |

Rules:

- **Branch protection requires only `CI OK`.** A new job must be added to `ci-ok`'s `needs`, or it gates nothing. Live ruleset: `gh api repos/sebyx07/zsv-ruby/rulesets`.
- `bin/repo-guards` (run by `bin/check` and by the `workflows` job) fails when `ci.yml` stops running the full `bin/check` or the guards, when a file agents read (`CLAUDE.md`, nested `CLAUDE.md`, `AGENTS.md`, `.claude/**`, `.dz/**`, `llms.txt`, `.mcp.json`) holds a zero-width or bidi character or an HTML comment, when committed settings set `ANTHROPIC_BASE_URL` or `enableAllProjectMcpServers`, when the root `CLAUDE.md` or `.dz/maintainer/reviewer.md` reaches 12,000 characters, or when `ZSV::VERSION` is ahead of the zsv pin.
- `bin/check` **is** the `check` job. It does not run the Ruby x OS matrix, the sanitizers (`bin/check asan` does, on Linux), the package build or the workflow linters. Green locally can still be red in CI; read the failed job, its step names the command.
- The sanitizer flags live in two places that must agree: the `sanitizers` job and `ASAN_CFLAGS` / `ASAN_LDFLAGS` / `asan_rspec` in `bin/check`.
- The matrices in `ci.yml` and `canary.yml` are the only place supported Rubies and platforms are listed. Docs link here; never copy the list. Windows is not in the matrix (the vendored zsv builds through `./configure` + `make`).
- The Ruby floor changes in three places together: `required_ruby_version` in the gemspec, the lowest `test` matrix row, `CHANGELOG.md` (breaking).
- Actions are pinned to a commit SHA with the version in a trailing comment; `persist-credentials: false` on checkout; top-level `permissions: contents: read`, widened per job only. zizmor fails the build otherwise. A new exception goes in `zizmor.yml` with the reason.
- Editing a workflow: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:<version in ci.yml> -color` before pushing.
- A red canary never blocks a PR; fix it in its own PR before the upstream release ships.

## Release lane

Source of truth: `RELEASE.md`. Prepare with `/release` (`.claude/commands/release.md`).

1. Version: gem `X.Y.Z` wraps zsv `X.Y.Z` (the pin in `ext/zsv/ZSV_UPSTREAM`); a gem-only release is `X.Y.Z.N`. The pin moves first, in its own `chore: zsv X.Y.Z` PR (skill `upgrade-zsv`, `.dz/schedules/upstream-zsv.md`).
2. PR titled `release: <version>`: set `VERSION` in `lib/zsv/version.rb`; move `## [Unreleased]` in `CHANGELOG.md` into `## [<version>] - YYYY-MM-DD`, leaving an empty `Unreleased`. Check: `.github/scripts/changelog-notes.sh <version>`.
3. `CI OK` green, merge. **The merge is the release.**
4. `release.yml`: `version` (reads `VERSION`, asks rubygems.org and GitHub what already exists) → `verify` (the whole `ci.yml`) → build (`native-gems.yml`) → `publish` (RubyGems trusted publishing, OIDC, environment `release`, no API key; platform gems first, the source gem last) → `github-release` (tag `v<version>`, notes from the CHANGELOG, gems attached).

Rules:

- Never `gem push`, `rake release` (it aborts on purpose), or push a `v*` tag. The tag is an output of the release, created after RubyGems has the gems.
- A merge that does not change `version.rb` publishes nothing. Do not write "released" in a PR or issue until the gem is on rubygems.org: `gem info zsv --remote`.
- A published version is never pushed again and never reused. Recovery for each failure point: `RELEASE.md` § If a release fails. A broken release: the owner yanks it, the fix is the next version.
- The weekly `release-due` checkup (`.dz/schedules/release-due.md`) decides when a release PR is opened; a fix for a published high or critical advisory in what ships is the one release the owner may cut off-cycle.
- A breaking change needs the owner's decision before merge.
