# shellcheck shell=bash
# Shared helpers for bin/setup, bin/check and bin/console. Sourced, never run.
# shellcheck disable=SC2034  # variables here are read by the scripts that source this file
#
# Exit codes used by every script:
#   0   success
#   75  an environment prerequisite is missing (ruby, gems, a C compiler, the compiled
#       extension): the script refused to run; fix the box (usually `bin/setup`), not the code
#   *   the script ran and something failed

EX_ENV=75

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { printf '\n▸ %s\n' "$*"; }
ok() { printf '  ✔ %s\n' "$*"; }

# env_missing <what is missing> <how to fix it> — exits 75.
env_missing() {
  {
    printf '\nENVIRONMENT MISSING (exit %s): %s\n' "$EX_ENV" "$1"
    printf '  fix: %s\n' "$2"
  } >&2
  exit "$EX_ENV"
}

# Puts the Ruby named in .ruby-version first on PATH (mise, then rbenv).
# `use_ruby install` also installs it; without the argument a missing Ruby is exit 75.
# ZSV_ANY_RUBY=1 accepts whatever Ruby is active (CI's matrix legs set it: they test other Rubies).
use_ruby() {
  local want have dir
  want="$(tr -d '[:space:]' <"$ROOT/.ruby-version")"
  want="${want#ruby-}"

  if [ "${ZSV_ANY_RUBY:-}" = 1 ]; then
    command -v ruby >/dev/null 2>&1 || env_missing "no ruby on PATH (ZSV_ANY_RUBY=1)" "install a Ruby"
    return
  fi

  if command -v mise >/dev/null 2>&1; then
    # mise refuses to resolve anything next to an untrusted mise.toml. Trust the repo's own
    # file for this process; bin/setup also records the trust so plain `ruby` works in a shell.
    export MISE_TRUSTED_CONFIG_PATHS="$ROOT${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
    if [ "${1:-}" = install ] && [ -f "$ROOT/mise.toml" ]; then mise trust --quiet "$ROOT/mise.toml"; fi
    if [ "${1:-}" = install ] && ! mise where "ruby@$want" >/dev/null 2>&1; then
      mise install "ruby@$want" ||
        env_missing "mise could not install ruby $want" "mise install ruby@$want"
    fi
    if dir="$(mise where "ruby@$want" 2>/dev/null)"; then PATH="$dir/bin:$PATH"; fi
  elif command -v rbenv >/dev/null 2>&1; then
    if [ "${1:-}" = install ]; then
      rbenv install --skip-existing "$want" ||
        env_missing "rbenv could not install ruby $want" "rbenv install $want"
    fi
    export RBENV_VERSION="$want"
    PATH="$(rbenv root)/shims:$PATH"
  fi
  export PATH

  have="$(ruby -e 'print RUBY_VERSION' 2>/dev/null || true)"
  [ -n "$have" ] ||
    env_missing "ruby $want is not installed" "install mise (https://mise.jdx.dev) or rbenv, then run bin/setup"
  [ "$have" = "$want" ] ||
    env_missing "ruby $have is active but .ruby-version wants $want" \
      "run bin/setup (installs it through mise or rbenv), or ZSV_ANY_RUBY=1 to use the active Ruby"
}

# require_gems — exit 75 unless the bundle is installed.
require_gems() {
  (cd "$ROOT" && bundle check >/dev/null 2>&1) ||
    env_missing "the bundle is not installed (or the Gemfile / gemspec changed)" "bin/setup"
}

# require_toolchain — exit 75 unless a C compiler and make are on PATH (the extension and the
# vendored zsv library are built from source).
require_toolchain() {
  local cc
  cc="$(ruby -e 'print RbConfig::CONFIG["CC"].split.first' 2>/dev/null || echo cc)"
  command -v "$cc" >/dev/null 2>&1 ||
    env_missing "no C compiler ($cc) on PATH" "install build tools (Debian/Ubuntu: apt install build-essential; macOS: xcode-select --install)"
  command -v make >/dev/null 2>&1 ||
    env_missing "make is not on PATH" "install build tools (Debian/Ubuntu: apt install build-essential; macOS: xcode-select --install)"
}

# extension_built — true when a compiled extension is in lib/zsv/.
extension_built() {
  compgen -G "$ROOT/lib/zsv/zsv.so" >/dev/null || compgen -G "$ROOT/lib/zsv/zsv.bundle" >/dev/null
}
