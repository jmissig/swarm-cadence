# Linux portability: first-pass verification

The source now has conditional Darwin/Glibc and FoundationNetworking imports,
explicit Dispatch imports, Foundation-based standard-error output, and Swift
Crypto hashing. Foundation's `URL.applicationSupportDirectory` now supplies the
platform-specific base for config and data, with `swarm-cadence` appended.
macOS paths remain unchanged; Linux uses `$XDG_DATA_HOME/swarm-cadence`, falling
back to `~/.local/share/swarm-cadence`. No existing files are moved.

## Verification status

- macOS, Swift 6.2.4: warnings-as-errors build and all 129 offline tests passed,
  including SHA-256 known-answer checks and HTTP transport fixtures.
- CLI version/help/error output and a synthetic export import/venue/visit query
  passed on macOS using a temporary database. No live credentials or network
  were used by these checks.
- Linux: not built or executed yet. Linux verification is an operator handoff;
  no Linux environment was installed for this work.
- The first target is glibc-based Linux. Alpine/musl and other platforms have
  not been assessed.

## Linux check

Use Swift 6.2 or newer and the system SQLite development package
(`libsqlite3-dev` on Debian/Ubuntu). Run from the repository root:

```sh
swift --version
swift test -Xswiftc -warnings-as-errors
swift run --skip-build swarm-cadence --version
swift run --skip-build swarm-cadence --help
```

Package resolution may download dependencies. Tests use offline fixtures and
temporary paths, not real account credentials or evidence stores.

For a human-readable import/query smoke check after the build:

```sh
smoke_dir="$(mktemp -d)"
mkdir "$smoke_dir/export"
cp Tests/Fixtures/FoursquareExport/2026-04-29-checkins1.json "$smoke_dir/export/checkins1.json"
swift run --skip-build swarm-cadence db import-files \
  --account fixture --db "$smoke_dir/fixture.sqlite" \
  --path "$smoke_dir/export" --format text
swift run --skip-build swarm-cadence query venues \
  --account fixture --db "$smoke_dir/fixture.sqlite" --format text
swift run --skip-build swarm-cadence query visits \
  --account fixture --db "$smoke_dir/fixture.sqlite" \
  --venue-id synthetic-export-venue --format text
```

Expect two inserted check-ins, one venue named `Synthetic Export Cafe`, and one
visit to that venue. One check-in intentionally lacks venue metadata; the
import's quality report is expected. The temporary directory contains only
synthetic smoke-test output and can be discarded afterward.

## Remaining boundaries

- GRDB 7.10.0 has contributor-maintained Linux support; verify the actual
  compiler, SQLite linking, and runtime behavior before claiming compatibility.
- Verify Foundation's default path and `XDG_DATA_HOME` handling on Linux.
  Config and data share one app root. `SWARM_CADENCE_APP_SUPPORT_DIR` overrides
  that root; explicit path options still take precedence. Tests inject temporary
  app roots without changing the process environment or visiting real user data.
- Packaging, installers, CI, and distribution/architecture coverage remain
  separate follow-ups. Record the Linux distribution, architecture, Swift
  version, and test results when verification is performed.
