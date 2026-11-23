# Security Policy

## Supported versions

Only the latest release on [RubyGems](https://rubygems.org/gems/zsv) gets security fixes. Fixes land on `main` and ship in the next release.

## Reporting a vulnerability

**Report privately through GitHub: [Report a vulnerability](https://github.com/sebyx07/zsv-ruby/security/advisories/new)** (the repository's Security tab → Advisories → Report a vulnerability). **Do not open a public issue or pull request:** both are public, and an AI agent triages them in the open.

Include:

- what is affected: the gem version (`gem list zsv`), the Ruby version, the OS and CPU architecture
- steps to reproduce, ideally the smallest input (attach the bytes, not a description of them) and the exact call with its options
- the impact as you understand it (crash, out-of-bounds read or write, wrong data)

There is no fixed response time. Reports are read and fixed as maintainer time allows, and you are credited in the changelog unless you ask not to be.

## In scope

- Memory safety in the C extension (`ext/zsv/*.c`): out-of-bounds reads or writes, use after free, double free, or a crash of the Ruby process on crafted input or a crafted sequence of calls
- The same in the zsv parser code this gem compiles and ships (`ext/zsv/vendor/zsv/src`, `include`). Those are also upstream's: please report them to [liquidaty/zsv](https://github.com/liquidaty/zsv) as well, and say here which zsv release fixes it
- Unbounded memory or CPU on input that is small on disk, where the gem documents streaming behaviour
- Anything in the published gem or its build and release pipeline that runs code a user did not ask for, including a vendored source tree that does not match the pinned upstream tarball (`ext/zsv/ZSV_UPSTREAM`)

## Out of scope

- zsv's command-line tools and extensions: the gem does not build or ship them
- CSV or formula injection in the data itself: the gem returns field bytes as they are; what a spreadsheet later does with them is the application's concern
- Reading a file path the calling application chose to pass in
- Development and benchmark tooling that is not packaged in the gem
