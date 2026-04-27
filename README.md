# swarm-cadence

`swarm-cadence` is a small local-first CLI for preserving and querying
Foursquare Swarm check-in history as private evidence for OpenClaw/Robut.

It currently supports:

- explicit source probes for Foursquare v2 and Swarm web `historysearch` config;
- one-request raw v2 check-in response preservation;
- offline SQLite import from preserved raw v2 files;
- aggregate database stats.

It does not make recommendations, run hidden background sync, write to
Foursquare/Swarm, or inspect raw payloads during routine commands.

## Build and Test

```bash
swift build
swift test
```

In sandboxed environments that block SwiftPM's default cache paths, use
repo-local caches:

```bash
mkdir -p .tmp/home .build/clang-module-cache
HOME=$PWD/.tmp/home CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache swift test --disable-sandbox
```

## Configuration

Use `config/swarm-cadence.env.example` as a template and keep the real config
outside git:

```bash
cp config/swarm-cadence.env.example ./.swarm-cadence.env
```

Account labels are explicit:

```bash
--account julian
--account alice
```

The label determines the expected environment/config variable names. For
example, `--account julian` reads
`SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN` for v2 commands.

## Source Probe

Dry source probes validate local config shape only:

```bash
swift run swarm-cadence source probe --account julian --adapter v2 --format json --config ./.swarm-cadence.env
swift run swarm-cadence source probe --account julian --adapter historysearch --format json --config ./.swarm-cadence.env
```

Dry probes do not call Foursquare or Swarm. They report missing/present inputs
with sensitive values redacted.

Run the live v2 probe only when you explicitly want one read-only source
viability check:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env \
  --live
```

The live v2 probe performs one `GET /v2/users/self/checkins` request with
`limit=1`. It does not ingest, backfill, persist raw payloads, or write a
database.

## Raw v2 Preservation

After a live v2 probe succeeds, preserve one raw check-ins page explicitly:

```bash
swift run swarm-cadence raw fetch \
  --account julian \
  --adapter v2 \
  --config ./.swarm-cadence.env \
  --out data/raw/v2/checkins \
  --limit 250 \
  --offset 0
```

`raw fetch` performs exactly one request per invocation. `--limit` defaults to
`250` and cannot exceed `250`; `--offset` defaults to `0` and must be
non-negative.

The command writes one unmodified `*.raw.json` response and one adjacent
redacted `*.manifest.json`. Console output is a compact summary only. `data/`
is git-ignored; do not commit raw check-in data.

## Offline SQLite Import

Import preserved v2 raw files into a rebuildable local SQLite sidecar:

```bash
swift run swarm-cadence db import-raw \
  --db data/swarm-cadence.sqlite \
  --raw-dir data/raw/v2/checkins
```

The importer performs no network calls. It verifies each raw file against its
manifest SHA256, then upserts aggregate evidence tables for raw files,
check-ins, venues, categories, and check-in/category links.

Audit aggregate coverage:

```bash
swift run swarm-cadence db stats --db data/swarm-cadence.sqlite
swift run swarm-cadence db stats --db data/swarm-cadence.sqlite --format json
```

`db stats` reports counts and oldest/latest check-in timestamps only. It does
not print raw payload contents.

## Safety Boundaries

- Keep tokens, cookies, browser-session details, raw payloads, and SQLite files
  out of git.
- Use explicit `--account`, `--config`, `--db`, `--raw-dir`, and `--out` paths.
- Do not run `--live` or `raw fetch` as routine tests.
- Do not use one account's credentials for another account label.
- Treat the SQLite DB as rebuildable from preserved raw evidence.
- Prefer `--format json` for scripts and agents; `--json` is accepted as a
  shorthand where supported.

Detailed source setup and schema notes live in
[docs/source-probe-setup.md](docs/source-probe-setup.md). Pattern-intelligence
direction lives in
[docs/pattern-intelligence-proposal.md](docs/pattern-intelligence-proposal.md).
