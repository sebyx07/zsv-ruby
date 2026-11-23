# Post-merge fix sweep

Weekly sweep, Thursdays 23:00 UTC, OFFERED and off: the `fix-sweep` entry in
`.dz/maintainer/maintainer.yml` is commented out, and uncommenting it is the opt-in. It runs as a
devops task (`mode: devops`: a shell on a checkout, at most one pull request). It is the
developerz.ai platform's standard fix sweep, adapted to zsv-ruby: the changes merged into `main` in
the last 7 days, read again for the defects their own review let through, and fixed in one pull
request. Read `CLAUDE.md` first, and `ext/CLAUDE.md` when the week touched `ext/`: their invariants
bind every fix.

## 1. Find the touched area

```bash
bin/setup                 # exit 75 = the box lacks Ruby or a C compiler: stop and say so
git log --since='7 days ago' --first-parent --format='%h %s' origin/main
git diff --stat "$(git rev-list -1 --before='7 days ago' origin/main)" origin/main -- . ':!ext/zsv/vendor'
```

The touched area is those files and their direct callers: for a C function, every entry point that
reaches it (`foreach`, `parse`, `read`, `open`, `Parser#shift` / `each`, for a path, a String and
an IO source). Nothing merged, or only dependency bumps: say so and stop. A merged `chore: zsv
X.Y.Z` changed the vendored tree: never read it for defects (upstream's code), read what the
upgrade changed in our C and the specs instead.

## 2. Hunt

Read the touched area for, worst first:

- **memory safety**: a new `VALUE` field with no mark or no compaction line; a raw pointer
  (`RSTRING_PTR`, a `zsv_get_cell` result) kept across a call that can allocate or advance the
  parser; Ruby reached from the free path; an exception that can unwind through zsv's frames (a
  callback body outside `rb_protect`); `zsv_finish()` or `zsv_delete()` reachable twice
- **lifetime**: a `FILE *`, zsv parser or buffer leaked when options, `#read` or the block raise,
  on `break`, on a second `close` or `#initialize`; a module method that does not close in `ensure`
- **correctness**: rows that differ from Ruby's `CSV` for a documented option; an ignored
  `enum zsv_status`; an option accepted and ignored; data dropped with no error; an unchecked
  `size_t` / `long` narrowing
- **cost**: work added per row or per cell on the hot path (`ext/zsv/row.c`, the row handler)
- **reuse**: a new copy of a helper `ext/zsv/common.h`, `lib/zsv/options.rb` or `spec/` already
  has; name both
- **drift**: a line in `README.md`, `docs/API_REFERENCE.md`, `llms.txt` or a `CLAUDE.md` that the
  merged change made false; a user-visible change with no line under `## [Unreleased]`

Confirm before you claim: a defect is one you can make fail.

## 3. Fix

- One pull request for the whole sweep, one goal: the defects this week's merges brought in.
- For each defect, a spec that fails before the fix and passes after. Run it red first. A wrong
  row is asserted against `CSV`'s own answer (`csv_rows`), never a literal; a lifetime defect is
  reproduced under `GC.stress = true` (and `GC.verify_compaction_references` for a stored `VALUE`)
  or by `bin/check asan` (skill `debug-gc`).
- Delete what the fix makes dead.
- `bin/check` must be green before you open the pull request, and `bin/check asan` too when the
  fix touches `ext/zsv/*.{c,h}`. Exit 75 is a missing environment, not a pass and not a failure:
  say what was not graded. One compile at a time in the checkout.
- A user-visible fix gets a `CHANGELOG.md` line under `## [Unreleased]`.
- A defect you cannot make fail is not fixed here: name it in the report, with no pull request for
  it.
- A fix that changes the rows returned for an input that parsed before, an option's default or the
  public API is breaking: report it for the owner.
- Do not edit `.github/`, `.dz/`, `bin/`, the `Rakefile`, the gemspec, `ext/zsv/extconf.rb`,
  `ext/zsv/ZSV_UPSTREAM`, anything under `ext/zsv/vendor/`, or `lib/zsv/version.rb`.

No defect: no pull request. A clean week is a good result; say so and stop.

## Report

The range of merges you read, each defect with its `path:line`, its test and its fix, what each
gate printed (`bin/check`, `bin/check asan`), and what you could not cover, with why.
