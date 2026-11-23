# Direction

> **Draft for the owner to correct.** Written on 2026-11-23 from `README.md`, `CHANGELOG.md`
> (1.3.0, 1.4.3 and `## [Unreleased]`, which pull request #6 fills) and the merged pull requests
> (#3, #4, #5); nothing here was stated by the owner. Every line is a reading of what the project
> already does, not a new goal. Edit it in place, then remove this note. Until then, agents treat
> it as maintenance guidance only, and `scout.survey` stays at its default (`broken_only`) in
> `.dz/maintainer/maintainer.yml`.

## What the product is for

Parsing CSV in Ruby faster than the `CSV` standard library, with the same reading API, by wrapping
the zsv C library in a native extension. A user changes `CSV.foreach` to `ZSV.foreach` and gets the
same rows. Readers: Ruby applications that read CSV files, Strings and streams, and AI coding
tools that read `llms.txt`. It parses only: the README sends writing, converters and `CSV::Table`
back to `csv`.

## What "better" means here

Ranked as the merged and pending work ranks it; the order is a reading, not a decision:

1. **It never crashes or corrupts the process it runs in.** Under `## [Unreleased]` → Fixed: the
   `[BUG] Aborted` in `ZSV.parse`, exceptions no longer raised through zsv's frames, GC compaction
   support, no leak when options, `#read` or the block raise.
2. **It never loses data silently.** Under Fixed: rows longer than the buffer or wider than 1024
   fields now raise instead of being cut; under Changed — breaking: unknown options and
   unsupported values raise `ArgumentError` instead of being ignored.
3. **The rows are `CSV`'s rows.** Under Changed — breaking: blank lines, short rows and duplicate
   headers now match `CSV`; under Added: `parse_line`, `headers:` as a String, read modes, strict
   mode, IO sources.
4. **It follows zsv.** The gem version is the zsv version: #4 (zsv 1.3.0 → 1.4.3) and the 1.4.4
   upgrade under `## [Unreleased]` → Changed.
5. **It installs anywhere, offline.** Under Security / Packaging: the zsv source is vendored and
   pinned by SHA-256, nothing is downloaded at install; under Added: precompiled gems; under
   Changed — breaking: source builds target the baseline CPU.
6. **It keeps up with Ruby.** #3 (Ruby 4.0 in CI, automated releases) and #5 (Ruby 4.0.10 for a
   security advisory).
7. **It is fast, and says so only with a run behind it.** The README's claim is "fast", with
   numbers left to the Benchmarks workflow; the baseline-CPU entry under `## [Unreleased]` reports
   a measured comparison instead of a figure.

## Out of bounds

The policy's `triage.non_goals` in `.dz/maintainer/maintainer.yml` is the list (no network at
install, no system or unpinned libzsv, no edits to the vendored source, no version that does not
mirror zsv, no runtime dependency, no unmeasured speed claim, among others). It is linked here, not
copied.

## Open questions for the owner

- Is the ranking above right, in particular parity with `CSV` (3) above following zsv (4)?
- The README says "Windows is not supported yet": is Windows support wanted?
- A JRuby pull request (#1) was closed unmerged: is JRuby out of scope for good?
- Should the gem ever write CSV or take converters, or does it stay a parser?
- zsv 1.4.4 added a per-cell malformed-UTF-8 handler "this gem does not use yet" (`CHANGELOG.md`):
  is using it wanted?
- The version follows zsv, not Semantic Versioning, so breaking changes ship without a major bump:
  is that the intended contract for the long run?
