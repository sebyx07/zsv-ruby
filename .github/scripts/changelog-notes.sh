#!/usr/bin/env bash
# Print the body of the "## [VERSION]" section of CHANGELOG.md (used by
# release.yml as the GitHub Release notes). Fails when the section is missing
# or empty, so a release cannot ship without notes.
#   .github/scripts/changelog-notes.sh 0.3.0
set -euo pipefail

version="${1:?usage: $0 VERSION}"
changelog="${CHANGELOG:-CHANGELOG.md}"

notes=$(awk -v header="## [$version]" '
  index($0, "## [") == 1 { if (found) exit; if (index($0, header) == 1) { found = 1; next } }
  found { print }
' "$changelog" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$(printf '%s' "$notes" | tr -d '[:space:]')" ]; then
  echo "::error::$changelog has no notes under '## [$version]'. Move the Unreleased entries into a dated '## [$version] - YYYY-MM-DD' section." >&2
  exit 1
fi
printf '%s\n' "$notes"
