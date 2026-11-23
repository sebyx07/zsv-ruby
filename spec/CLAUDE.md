# spec/ — the suite

RSpec against the **compiled** extension in `lib/zsv/` (`spec_helper.rb` requires `zsv`). No extension, no suite: `bin/setup`. One compiled artifact per checkout: when agents share it, run `bin/check files spec/<file>_spec.rb` (never compiles) and let the build's owner compile.

| Path | Holds |
|---|---|
| `spec_helper.rb` | RSpec config (`.rspec_status` for `--only-failures`, no monkey patching), `with_csv_file(content) { |path| }` (a file in a temporary directory, removed after the block) |
| `zsv_spec.rb` | Behaviour of the public API: module methods, `ZSV::Parser`, headers, options, errors, lifecycle |
| `api/csv_compat_spec.rb`, `api/csv_compat_helper.rb` | Parity with Ruby's `CSV`: `csv_rows(data, **options)` is `CSV`'s own answer for the same input |

## Rules

1. **Parity is asserted against `CSV`, not a literal.** `expect(ZSV.parse(data, **opts)).to eq(csv_rows(data, **opts))`. A literal expected value proves only that ZSV agrees with whoever typed it. A difference from `CSV` that is intended is asserted explicitly, with a comment naming the row of `docs/API_REFERENCE.md` that documents it.
2. A new or changed option gets parity cases over the awkward inputs, not just the happy one: empty fields (quoted and unquoted), quoted delimiters and newlines, escaped quotes, CRLF and lone CR, a BOM, ragged rows, blank lines, duplicate and empty headers, no trailing newline, empty input, a field longer than the read buffer, non-ASCII bytes. Add the input to the shared table in `csv_compat_spec.rb` so every entry point gets it.
3. **Every entry point.** Behaviour holds for a path, a String and an IO source, and for `foreach`, `parse`, `read`, `open` and `Parser#shift` / `each`: they take different routes through the C.
4. **Lifetime specs run under GC pressure.** Anything that touches what the C stores or frees is exercised with `GC.stress = true` (reset in `ensure`), and with `GC.verify_compaction_references(expand_heap: true, toward: :empty)` when a stored `VALUE` is involved (guard with `GC.respond_to?(:compact)`). Walk the paths in `ext/CLAUDE.md` § Proving a C change: close twice, close inside `each`, `break`, a raising block, a raising `#read`, rewind, a parser dropped unclosed then `GC.start`.
5. **`:slow`** tags an example that takes more than about a second (GC-stress loops, large generated inputs). `bin/check fast` skips them; `bin/check` and CI run everything. Never use the tag to park a failing spec.
6. No `skip`, `pending` or `xit` to get green, and no retry loops around a flaky example: a spec that fails sometimes is a memory bug until proven otherwise (skill `debug-gc`).
7. Specs hardcode inputs and build files with `with_csv_file`; they never read fixtures from outside the repo or the network, and never depend on example order.
8. A crash cannot be asserted in-process. Reproduce it in a child (`ruby -Ilib -e …` through `Open3`) only when the test is that the child exits cleanly; otherwise the proof is `bin/check asan`.
9. Performance is not asserted in specs (timing on shared runners is noise). It lives in `benchmark/` and the `benchmark.yml` run summaries.
