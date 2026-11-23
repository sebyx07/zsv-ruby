# Releasing zsv

`ZSV::VERSION` in `lib/zsv/version.rb` is the single source of truth.
**Merging a pull request that changes it is the release.** Nobody tags or runs
`gem push` by hand: the tag is an output of the release, created only after
RubyGems has the gems.

## Versioning

Gem `X.Y.Z` wraps the zsv C library `X.Y.Z` pinned in `ext/zsv/ZSV_UPSTREAM`
(`bin/repo-guards` enforces it). A gem-only fix appends a fourth segment
(`1.4.4.1`, tagged `v1.4.4.1`). A prerelease uses the RubyGems letter form
`1.5.0.rc1`, tagged `v1.5.0-rc1` and marked as a prerelease on GitHub.
Upgrading zsv is its own pull request (`rake "zsv:bump[X.Y.Z]"`), merged before
the release.

## Cutting a release

1. Set `VERSION` in `lib/zsv/version.rb`.
2. In `CHANGELOG.md`, rename the filled `## [Unreleased]` section to
   `## [<version>] - YYYY-MM-DD` and leave an empty `Unreleased` on top. That
   section's body becomes the GitHub Release notes verbatim, so write it for
   users. Check it: `.github/scripts/changelog-notes.sh <version>`.
3. `bin/check`, then open the pull request titled `release: <version>` with only
   the bump in it. Let `CI OK` go green, merge.

The `/release` command (`.claude/commands/release.md`) does these steps.

## What CI does (`.github/workflows/release.yml`)

On a push to `main` that touches `lib/zsv/version.rb` (or a manual run on `main`):

1. **version**: reads `VERSION`, asks rubygems.org whether the source gem of
   that version exists, and whether the GitHub Release exists. A tag already
   pointing at another commit for an unpublished version fails the run, and so
   does a missing CHANGELOG section.
2. **verify**: the whole CI workflow (`ci.yml`), only if the version is not on
   RubyGems yet.
3. **build** (`native-gems.yml`): the source gem (`rake build`, which must
   install with the network disabled) and one precompiled gem per platform in
   the Rakefile's `NATIVE_PLATFORMS` (`rake gem:native:<platform>`, through
   rake-compiler-dock). Every precompiled gem is installed on a runner of its
   own platform, on every supported Ruby, and must load and parse without
   compiling anything.
4. **publish**: `gem push` of the gems built in step 3, through RubyGems trusted
   publishing (OIDC, environment `release`): the platform gems first, the source
   gem last. Any gem already on RubyGems is skipped, so a published file is never
   pushed again. The source gem going last means "the source gem is on RubyGems"
   (what step 1 checks) only becomes true once every platform gem is there.
5. **github-release**: creates tag `v<version>` and the GitHub Release with the
   CHANGELOG notes and every `.gem` attached. After a publish in the same run the
   tag is the commit that was built. When publish was skipped (see below) the tag
   is the newest commit on `main` that set that `VERSION`, and the attached gems
   are downloaded from RubyGems, never rebuilt.

Adding or dropping a platform is a Rakefile change (`NATIVE_PLATFORMS`); the
`plan` job of `native-gems.yml` maps each platform to the runner that
smoke-tests it and fails, naming itself, for a platform it does not know.
`canary.yml` builds all of them monthly, so a broken cross-build shows up before
a release needs it. To try it on a branch: Actions → Native gems → Run workflow.

## If a release fails

- **Before any gem was pushed** (version, verify or build failed): fix on `main`
  and keep the same version. The next push to `version.rb` or a manual run
  (Actions → Release → Run workflow, on `main`) starts over.
- **Some gems were pushed, the source gem was not** (publish failed midway):
  re-run the workflow on `main`. Step 1 still sees the version as unpublished,
  rebuilds, and publish pushes only what RubyGems lacks.
- **The gems are on RubyGems, only the GitHub step failed**: re-run the failed
  job, or run the workflow by hand on `main`. It sees the version on RubyGems,
  skips verify, build and publish, and creates the tag and release. Commits
  merged since do not matter: the tag goes on the commit that set `VERSION`, and
  the assets are the gems RubyGems serves. Do this before the next version bump
  merges: the run reads `VERSION` from `main`, so once `main` names a newer
  version the older release has to be created by hand
  (`gh release create v<version> --target <the commit that set it>`).
- A version that reached RubyGems is never pushed again and never reused. A
  broken one is yanked by the owner (`gem yank zsv -v <version>`, with
  `--platform` for one platform gem) and fixed in the next version.

Never run `rake release` (Bundler's task, which would push from a laptop and
bypass the gate) or push a `v*` tag yourself.

## One-time setup

- rubygems.org → zsv → Trusted publishers → GitHub Actions: repository
  `sebyx07/zsv-ruby`, workflow `release.yml`, environment `release`.
- GitHub → Settings → Environments → `release`: deployment branches `main`
  only. No secrets are needed. Required reviewers are optional: they turn every
  release into a manual approval.
- GitHub → Settings → Rules → the `main` ruleset: the only required status
  check is `CI OK`.
