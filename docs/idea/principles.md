# Principles

The product's promises are the invariants in `CLAUDE.md` § Invariants; this page says why they
exist, and does not restate them.

- **The user's process is not ours to crash.** A C extension has no exception to fall back on: an
  unmarked object, a pointer kept too long or an exception thrown through zsv's frames is a
  segfault or silent corruption in someone's application. That is why the C rules (`ext/CLAUDE.md`)
  come before every other concern, and why a spec that fails sometimes is treated as a memory bug.
- **Wrong rows are worse than no rows.** A parser that drops a field or cuts a row short corrupts
  data downstream without anyone noticing. Limits raise, unknown options raise, every zsv status
  is checked.
- **`CSV` is the specification.** Users switch by changing a constant, so for every option the
  docs list as compatible the rows are the ones `CSV` returns, and the specs compare against
  `CSV`'s own output. Each intended difference is written down (`docs/API_REFERENCE.md`
  § Differences from CSV).
- **The gem is what upstream is.** The version mirrors zsv so a user knows which parser they run;
  the source is vendored and pinned by hash so the build is reproducible, reviewable and offline.
  zsv bugs are fixed upstream, never patched in the vendored tree.
- **Installing is boring.** No network, no system library, no CPU-specific binary: a gem built on
  one machine runs on another of the same architecture.
- **Numbers are measured.** Speed is the reason to use the gem, so a figure nobody can reproduce
  is a defect in the docs. Current numbers are the Benchmarks workflow's run summaries.
