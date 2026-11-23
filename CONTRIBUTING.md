# Contributing

Bug reports and pull requests are welcome at https://github.com/sebyx07/zsv-ruby. AI-assisted contributions are welcome too; the same checks apply.

## Setup

Requirements: the Ruby in `.ruby-version` (mise or rbenv), a C compiler and `make`. No network is needed to build: the zsv C source is vendored in the repository.

```bash
bin/setup                  # Ruby, gems, compile the extension; safe to rerun
bin/check                  # the gate: repo guards, RuboCop, clang-format, compile, full RSpec (what CI runs)
bin/check fast             # inner loop: lint on changed files, incremental compile, specs not tagged :slow
bin/check files <path>...  # only the named files; never compiles
bin/check asan             # the suite under AddressSanitizer + UBSan (Linux, gcc)
bin/console                # IRB with ZSV and CSV loaded
bundle exec rake bench     # benchmarks against Ruby's CSV
```

Exit code 75 from any script means the environment is missing something, not that a check failed: run `bin/setup`. Each script documents itself in its header comment.

## Where things are

| Path | What |
|---|---|
| `ext/zsv/*.c`, `*.h` | The C extension: `parser.c` (zsv's callbacks bridged to `shift` / `each`), `row.c` (cells to Ruby rows), `options.c`, `zsv_ext.c` (Ruby bindings, GC functions) |
| `ext/zsv/extconf.rb` | Builds the vendored zsv into a static library and links it. Offline |
| `ext/zsv/ZSV_UPSTREAM` | The pinned zsv release: version and tarball SHA-256 |
| `ext/zsv/vendor/zsv/` | The vendored zsv source. Written by `rake zsv:vendor` only; never edited by hand |
| `lib/zsv.rb`, `lib/zsv/` | The Ruby API |
| `spec/` | RSpec suite, including parity specs against Ruby's `CSV` |
| `benchmark/` | benchmark-ips scripts run by `rake bench` |
| `docs/` | API reference and quick start |

Rules for agents and the full code map: [CLAUDE.md](CLAUDE.md) and [ext/CLAUDE.md](ext/CLAUDE.md). User reference: [docs/API_REFERENCE.md](docs/API_REFERENCE.md), [llms.txt](llms.txt).

## Pull requests

1. Branch from `main`; keep the pull request focused on one change.
2. Add or adjust specs for every behaviour change. A new or changed option needs a spec comparing against Ruby's `CSV` for the same input.
3. C changes follow [ext/CLAUDE.md](ext/CLAUDE.md): every stored `VALUE` is marked, nothing allocates or raises on the free path, `zsv_finish` runs exactly once per parser, and resources are released when Ruby code raises. Run `bin/check asan`, and cover lifetime changes with a spec under `GC.stress`.
4. A change to the hot path, or any speed claim, comes with `bundle exec rake bench` output from before and after, with the Ruby version and CPU.
5. Do not edit `ext/zsv/vendor/`, `ext/zsv/ZSV_UPSTREAM` or `lib/zsv/version.rb` by hand. The pin and the vendored tree change only through `bundle exec rake "zsv:bump[X.Y.Z]"` in a pull request of its own; `version.rb` changes only in a release pull request ([RELEASE.md](RELEASE.md)). A parser bug inside zsv belongs [upstream](https://github.com/liquidaty/zsv/issues).
6. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
7. Update [README.md](README.md), `docs/` and [llms.txt](llms.txt) when methods, options or behaviour change.
8. Run `bin/check` before marking the pull request ready.

The pull request template carries this checklist.

## Style

Ruby: RuboCop (`.rubocop.yml`). C: clang-format (`.clang-format`), applied to `ext/zsv/*.c` and `*.h` only. Follow the patterns in the file you are editing.

## Reporting bugs

Use the bug report form. The maintainer agent needs steps to reproduce (the input as a Ruby string literal and the exact call), the expected result, the actual result, the gem version and the environment (Ruby, OS, CPU architecture); a report missing them is asked for them before anything else happens.

Security problems, including any crash on crafted input, go through [SECURITY.md](SECURITY.md), never a public issue.

## How pull requests get merged

This repo is maintained by [developerz.ai](https://developerz.ai). Its agent reviews every pull request, may request changes, and merges every pull request (contributors, members, bots) once you mark it ready for review and CI is green; keep it a draft until then. The policy is in [`.dz/maintainer/maintainer.yml`](.dz/maintainer/maintainer.yml). Commit with an email linked to your GitHub account.

Changes to CI, release, publishing or vendoring automation (`.github/`, `bin/`, the `Rakefile`, the gemspec, `ext/zsv/extconf.rb`, the zsv pin and vendored tree, `ZSV::VERSION`) are made by the owner only. Breaking changes are decided by the owner.

## Versions and releases

The gem version mirrors the zsv C library it wraps: gem `X.Y.Z` ships zsv `X.Y.Z`, and a gem-only release adds a fourth segment (`X.Y.Z.1`). A new zsv release is followed by a `chore: zsv X.Y.Z` pull request, then a `release: X.Y.Z` pull request. Releases are cut by merging a version bump: see [RELEASE.md](RELEASE.md).

## Conduct and license

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md). By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
