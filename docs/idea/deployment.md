# Deployment

One lane, from `main`, through GitHub Actions. Nothing is published by hand, and there is no server
or site.

- **The gem.** Merging a pull request that changes `ZSV::VERSION` in `lib/zsv/version.rb` is the
  release. `.github/workflows/release.yml` runs the whole CI workflow on that commit, builds the
  source gem and one precompiled gem per platform (`.github/workflows/native-gems.yml`), publishes
  them to RubyGems through trusted publishing (OIDC, no API key), then creates the tag and the
  GitHub release from the version's `CHANGELOG.md` section. Procedure and recovery: `RELEASE.md`.
- **Which version.** The gem version is not chosen: it mirrors the zsv pin. The monthly
  `upstream-zsv` task opens `chore: zsv X.Y.Z` when upstream ships a release, and the weekly
  `release-due` checkup then opens `release: X.Y.Z`. A gem-only release appends a fourth segment.
- **What users install.** A precompiled gem where one matches their platform, otherwise the source
  gem, which compiles the vendored zsv on install with no network access.

Outcome checks: the daily `health` checkup (`.dz/schedules/health.md`) verifies that `main` is
green, the last release run succeeded, RubyGems serves the version, the release is tagged and the
platform gems are complete. `.github/workflows/canary.yml` builds monthly against Ruby head and
upstream zsv, and `.github/workflows/benchmark.yml` posts `rake bench` output for each push to
`main`.
