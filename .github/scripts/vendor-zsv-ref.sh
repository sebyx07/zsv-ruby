#!/usr/bin/env bash
# Replace ext/zsv/vendor/zsv with liquidaty/zsv at an unpinned git ref, so the
# extension can be built against upstream before a release pins it. canary.yml
# uses this; never commit the result (`rake "zsv:bump[X.Y.Z]"` is how a release
# is pinned).
#   .github/scripts/vendor-zsv-ref.sh main            # the default branch
#   .github/scripts/vendor-zsv-ref.sh latest-release  # newest published release
#   .github/scripts/vendor-zsv-ref.sh v1.4.4          # any tag
#
# Copies the same top-level paths `rake zsv:vendor` keeps (ZSVUpstream::
# VENDORED_PATHS) and writes the marker of the current pin, so extconf.rb
# accepts the tree. The build still passes the pinned version number to make.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

ref="${1:?usage: $0 main|latest-release|<tag>}"
if [ "$ref" = latest-release ]; then
  ref=$(gh api repos/liquidaty/zsv/releases/latest --jq .tag_name) # needs GH_TOKEN in CI
fi
case "$ref" in
  v[0-9]*) url="https://github.com/liquidaty/zsv/archive/refs/tags/$ref.tar.gz" ;;
  *) url="https://github.com/liquidaty/zsv/archive/refs/heads/$ref.tar.gz" ;;
esac

upstream() { ruby -r ./ext/zsv/upstream -e "print $1"; }
vendor_dir=$(upstream 'ZSVUpstream::VENDOR_DIR')
mapfile -t keep < <(upstream 'ZSVUpstream::VENDORED_PATHS.join("\n")')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $url"
curl -sfL "$url" | tar -xz -C "$tmp" --strip-components=1

rm -rf "$vendor_dir"
mkdir -p "$vendor_dir"
for path in "${keep[@]}"; do
  if [ ! -e "$tmp/$path" ]; then
    echo "::error::zsv $ref has no top-level $path, which the vendored tree needs (ZSVUpstream::VENDORED_PATHS)." >&2
    exit 1
  fi
  cp -R "$tmp/$path" "$vendor_dir/"
done
ruby -r ./ext/zsv/upstream -e 'File.write(ZSVUpstream::MARKER_FILE, ZSVUpstream.marker_for(ZSVUpstream.pin))'
echo "Vendored zsv $ref into $vendor_dir (marker of the pinned $(sed -n 's/^version=//p' ext/zsv/ZSV_UPSTREAM))"
