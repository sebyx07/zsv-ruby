# Releasing

Releases are automated. Pushing a `v*` git tag triggers
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which:

1. Compiles the C extension and runs the test suite (release gate).
2. Verifies the tag matches `ZSV::VERSION` in `lib/zsv/version.rb`.
3. Builds the gem and pushes it to RubyGems via **trusted publishing** (OIDC —
   no API key secret stored in the repo).
4. Creates a GitHub Release with the gem attached.

## One-time setup

### 1. Configure RubyGems trusted publishing

On <https://rubygems.org>, for the `zsv` gem:

- Go to the gem's **Settings → Trusted publishers → Add trusted publisher**.
- Choose **GitHub Actions** and fill in:
  - Repository owner: `sebyx07`
  - Repository name: `zsv-ruby`
  - Workflow filename: `release.yml`
  - Environment (optional but recommended): `release`

> First publish only: if the gem name does not exist on RubyGems yet, trusted
> publishing can't be attached to a non-existent gem. Do the very first
> `gem push` manually (`gem build zsv.gemspec && gem push zsv-*.gem`), then add
> the trusted publisher so all later releases are automated.

### 2. (Recommended) Protect the `release` environment

In GitHub repo **Settings → Environments → release**, add required reviewers if
you want a manual approval gate before each publish.

## Cutting a release

1. Bump the version in `lib/zsv/version.rb`.
2. Add a section to `CHANGELOG.md` for the new version.
3. Commit:

   ```bash
   git add lib/zsv/version.rb CHANGELOG.md
   git commit -m "Bump version to X.Y.Z"
   git push origin main
   ```

4. Tag and push (CI does the actual publish):

   ```bash
   bundle exec rake release:tag
   ```

   This creates `vX.Y.Z` from the current `ZSV::VERSION`, refusing to run if the
   working tree is dirty or the tag already exists, and pushes it to `origin`.

5. Watch the **Release** workflow in the Actions tab. When it's green the gem is
   live on RubyGems and a GitHub Release exists.

## Notes

- The version in the tag **must** equal `ZSV::VERSION`; the workflow fails fast
  otherwise.
- Do **not** run `rake release` (the default Bundler task) — it would push the
  gem from your machine and bypass the CI gate. Use `rake release:tag` instead.
- `zsv-ruby` tracks the upstream zsv library version, so the gem's major/minor
  generally follow zsv's.
