# API

> established by the developerz.ai maintainer agent for the maintainers of this repository from what onboarding read and ran in this repo, then owned by
> its maintainers. Correct it in place; setup never overwrites a page that exists.

**Module methods:** `ZSV.foreach(source, **opts) { |row| }` streams rows; `ZSV.parse(csv_string, **opts)` → array of rows; `ZSV.read(path, **opts)` → array of rows; `ZSV.parse_line(csv_line)` → one row; `ZSV.open(source, **opts) { |parser| }` yields a parser; `ZSV::Parser.new(source, **opts)` for manual iteration.

**Options:** `headers` (true or array), `col_sep` (single ASCII char), `skip_lines` (number), `liberal_parsing` (bool; default true; set false to validate like CSV), `encoding` (labels returned strings; no transcoding), `buffer_size`, `max_columns`, `max_row_size`.

**Parser methods:** `shift` → one row or nil; `rewind` → restart; `close` → release resources; `headers` → header names (nil until first row read); `each { |row| }` → enumerator; `Enumerable` methods.

**Errors:** `ZSV::Error` (base), `ZSV::MalformedCSVError` (with `liberal_parsing: false`), `ZSV::InvalidEncodingError`. Bad options raise `ArgumentError` before any file opens. Full reference: `docs/API_REFERENCE.md`.
