# Brief: is the project healthy?

Daily checkup, fired by `schedules: health` in `.dz/maintainer/maintainer.yml`. zsv-ruby is
maintained so that nobody has to watch it. This covers the failures no issue or PR announces.
Read-only (a scout): it reports failing rows, it never re-runs a publish, tags, or pushes. A row
whose only fix is under `.github/` or `.dz/` is stated in the run's answer instead of filed: the
platform refuses a checkup filing that names CI or policy paths, and the monthly `improve` task
(`.dz/schedules/improve.md`) or the owner picks it up from there.

```bash
R=sebyx07/zsv-ruby
v=$(gh api "repos/$R/contents/lib/zsv/version.rb" --jq .content | base64 -d | sed -n "s/.*VERSION = '\(.*\)'.*/\1/p")
pin=$(gh api "repos/$R/contents/ext/zsv/ZSV_UPSTREAM" --jq .content | base64 -d | sed -n 's/^version=//p')
tag="v$v"
```

| Signal | Command | Healthy |
|---|---|---|
| `main` is green | `gh run list -R $R --workflow ci.yml --branch main --event push --limit 1 --json conclusion,headSha,url` | `success` (the `CI OK` job passed) |
| the last release published | `gh run list -R $R --workflow release.yml --limit 1 --json conclusion,displayTitle,url,createdAt` | `success`, or no run yet, or one in progress |
| RubyGems serves `ZSV::VERSION` | `curl -s -o /dev/null -w '%{http_code}' "https://rubygems.org/api/v2/rubygems/zsv/versions/$v.json"` (this exact version; `latest.json` skips prereleases) | `200`; or `404` while a `release.yml` run for `$v` is in flight or under 2 h old, or while `$pin` is ahead of `$v` (an upgrade is merged, its release PR is `release-due`'s). Any other code is a failed read, not a verdict |
| the release is tagged | `gh api "repos/$R/git/ref/tags/$tag" --jq .ref` and `gh release view "$tag" -R $R --json tagName` | both exist once RubyGems serves `$v` |
| the published gem installs | `gh run list -R $R --workflow release.yml --limit 1 --json conclusion,jobs` and, when RubyGems serves `$v`, `curl -s "https://rubygems.org/api/v1/versions/zsv.json" \| jq -r --arg v "$v" '.[] \| select(.number==$v) \| .platform'` | the source gem (`ruby`) is listed for `$v`; precompiled platforms, when `release.yml` builds them, are all listed or none is |
| version sync | compare `$v` and `$pin` | the first three segments of `$v` equal `$pin`, or `$pin` is newer than `$v` and the `chore: zsv $pin` merge is under 10 days old |
| Dependabot is not stuck | `gh pr list -R $R --author app/dependabot --state open --json number,title,createdAt,statusCheckRollup` | none open more than 7 days, none red more than 2 days |
| canary ran | `gh run list -R $R --workflow canary.yml --limit 1 --json conclusion,createdAt,url` | a run in the last 35 days (its failures belong to the monthly `upstream-zsv` and `improve` tasks, not this one) |
| the upstream check ran | `gh pr list -R $R --state all --search 'chore: zsv in:title' --limit 1 --json title,createdAt` and `gh api repos/liquidaty/zsv/releases/latest --jq '.tag_name + " " + .published_at'` | upstream's latest equals `v$pin`, or it was published under 40 days ago, or an open PR or issue names it |

If a workflow named above does not exist yet (`gh workflow view <file> -R $R` fails), that is the
row, not an error in this brief.

## Rows

Each failing row is filed once, with the exact title below, unless an open issue with that title (or the
same title prefix for rows with a variable) already exists: `gh issue list -R $R --state open --search '"<title>" in:title'`.
The body carries the command, its output and the run URL. A red `main` comes first: nothing
releases from it.

- `main-red` — title `main is red at <short sha>`: the last push run of `ci.yml` on `main` did not conclude `success`. If an older open `main is red at …` issue names another sha, or `main` is green again while one is open, say so in the answer with the run URL (this run closes nothing).
- `release-unpublished` — title `release v<version> did not publish`: the last `release.yml` run did not conclude `success`.
- `rubygems-version-lag` — title `RubyGems does not serve <version>`: RubyGems answers 404 for `$v`, `$pin` is not ahead of `$v`, and no release run is in flight or under 2 h old.
- `release-untagged` — title `<tag> is published but not tagged`: RubyGems serves `$v` but the `$tag` tag or GitHub release is missing.
- `release-platforms-partial` — title `<version> is missing platform gems`: some precompiled platform gems of `$v` are on RubyGems and others are not, or the source gem is missing.
- `version-out-of-sync` — title `gem <version> does not wrap zsv <pin>`: `$v` is ahead of `$pin`, or `$pin` has been ahead of `$v` for more than 10 days with no open `release: …` PR.
- `dependabot-stuck` — title `Dependabot PR #<n> is stuck`: a Dependabot PR open more than 7 days, or red more than 2 days. Say why it is stuck (red check, conflict, waiting on review) in the body.
- `canary-stale` — title `canary has not run in 35 days`: no `canary.yml` run in the last 35 days, or the workflow is missing.
- `upstream-zsv-unfollowed` — title `zsv <upstream version> is out and not followed`: upstream's latest release is newer than `$pin`, was published more than 40 days ago, and no open PR or issue names it (the monthly `upstream-zsv` task missed it).

Never delete a tag, re-run a publish, `gem push` or push to `main` from here.
