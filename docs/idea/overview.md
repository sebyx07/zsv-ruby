# Overview

zsv-ruby is the Ruby gem `zsv`: a CSV **parser** with the reading API of Ruby's `CSV` standard
library (`ZSV.foreach`, `parse`, `read`, `open`, `ZSV::Parser#shift` / `each`), implemented as a C
extension over [zsv](https://github.com/liquidaty/zsv), a SIMD-accelerated C library. It reads
from a path, a String or any IO, streams rows as the input is consumed, and returns Arrays or
Hashes of frozen Strings. It does not write CSV.

Its users are Ruby applications that parse CSV and want it faster without changing their call
sites, and AI coding tools that read `llms.txt`. The gem runs inside the user's process, so a bug
in the C is a crash or corrupted memory in their application, not an exception.

The zsv source is vendored in the repository and shipped inside the gem, pinned by version and
SHA-256, and the gem version mirrors it: gem `X.Y.Z` wraps zsv `X.Y.Z`.

It is a public project maintained by the developerz.ai agent under the policy in
`.dz/maintainer/maintainer.yml`. Where things live: `CLAUDE.md` § Architecture. The C rules:
`ext/CLAUDE.md`. What users are told: `README.md`, `docs/API_REFERENCE.md`.
