# swarm-cadence

`swarm-cadence` is a small local-first CLI for preserving and querying
Foursquare Swarm check-in history as private evidence for OpenClaw/Robut.

The first slices are intentionally narrow: the CLI validates local
configuration, can perform one explicit read-only v2 source probe, can preserve
one conservative raw v2 check-ins response, and can build a small local SQLite
index from preserved raw files. It does not make lunch recommendations.

The CLI uses a tiny dependency-free parser for this first offline slice.
Adopt `swift-argument-parser` once the command surface grows beyond the dry
probe.

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

## Dry Source Probe

The default command is dry config validation:

```bash
swift run swarm-cadence source probe --account julian --adapter v2 --format json
swift run swarm-cadence source probe --account julian --adapter historysearch --format json
```

Both commands perform dry config validation only. The JSON output includes:

- `probe_kind: "dry_config_validation"`
- `network_performed: false`
- `external_setup_required`
- required and optional input names
- redacted presence checks for sensitive values
- next actions for the selected adapter

Use `config/swarm-cadence.env.example` as a template:

```bash
cp config/swarm-cadence.env.example ./.swarm-cadence.env
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env
```

Do not commit real tokens, cookies, browser-session ids, OAuth params, or local
config files. The checked-in example contains placeholders only.

## Live v2 Source Probe

After storing a real v2 OAuth token outside git, run the live probe explicitly:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env \
  --live
```

`--live` performs one read-only request to
`GET https://api.foursquare.com/v2/users/self/checkins` with `limit=1` and a v2
API version parameter. It does not ingest, backfill, persist raw payloads, or
write a database.

The JSON result reports whether the source path is usable (`success`,
`unauthorized`, `payment_required`, `blocked`, `schema_unexpected`, or
`network_error`) and, on success, whether the returned sample includes useful
fields: check-in id, `createdAt`, venue id/name, lat/lng, categories, photos,
and count/date hints. Tokens and secrets are redacted from output and errors.

## Raw v2 Preservation

After the live v2 probe succeeds, preserve one raw response explicitly:

```bash
swift run swarm-cadence raw fetch \
  --account julian \
  --adapter v2 \
  --config ./.swarm-cadence.env \
  --out data/raw/v2/checkins \
  --limit 250 \
  --offset 0
```

This performs exactly one `GET /v2/users/self/checkins` request. There is no
pagination loop and no backfill. The default `--limit` is `250`; the command fails above the hard max of `250`
per invocation. The default `--offset` is `0`, and offsets must be
non-negative. The current Get User Checkins docs identify `250` as the endpoint
limit, so this uses the largest documented page size while still performing only
one request per invocation.

`--out` is required. The command writes:

- one `*.raw.json` file containing the unmodified Foursquare response bytes;
- one adjacent `*.manifest.json` file with redacted request metadata, HTTP/API
  status, returned/total counts when parseable, byte count, and SHA256.

Console output is a concise redacted summary: raw file path, manifest path,
bytes, status, returned count, and total count when parseable. Tokens are not
printed. `data/` is git-ignored; do not commit raw check-in data.

For a deliberate four-page sample of roughly 1000 check-ins, run four separate
commands after confirming the live v2 probe succeeds:

```bash
swift run swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 0
swift run swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 250
swift run swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 500
swift run swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 750
```

Each command still performs exactly one request and writes one raw file plus one
manifest.

## Offline SQLite Import

After preserving raw v2 pages, build or refresh the local SQLite sidecar without
calling the network:

```bash
swift run swarm-cadence db import-raw \
  --db data/swarm-cadence.sqlite \
  --raw-dir data/raw/v2/checkins
```

The importer reads adjacent `*.manifest.json` and `*.raw.json` pairs, verifies
the raw SHA256 from the manifest, parses
`response.checkins.items`, and upserts small provenance-preserving tables:
`raw_files`, `checkins`, `venues`, `categories`, and `checkin_categories`.
Rerunning the command is idempotent. Raw files and SQLite files under `data/`
remain git-ignored.

To audit aggregate coverage:

```bash
swift run swarm-cadence db stats --db data/swarm-cadence.sqlite
```

`db stats` reports table counts and oldest/latest check-in timestamps only. Use
`--format json` for machine-readable output.

## What Julian Needs To Do Next

To continue with the preferred v2 OAuth path:

1. Create or identify a Foursquare developer app.
2. Register a local redirect URI for the OAuth web flow.
3. Authorize the account, e.g. `julian`, and obtain an OAuth access token for
   that Swarm/Foursquare user.
4. Store the token outside git as
   `SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN`, either in the environment or in a
   git-ignored dotenv file passed with `--config`.
5. Optionally store setup breadcrumbs outside git:
   `SWARM_CADENCE_JULIAN_V2_CLIENT_ID`,
   `SWARM_CADENCE_JULIAN_V2_CLIENT_SECRET`, and
   `SWARM_CADENCE_JULIAN_V2_REDIRECT_URI`.

To prepare the fallback Swarm web `historysearch` path:

1. Log in to Swarm in a browser for the intended account.
2. Capture only the minimal authenticated `historysearch` request details
   needed for a future live probe.
3. Store them outside git as
   `SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID`,
   `SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID`, and
   `SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN`.
4. Store `SWARM_CADENCE_JULIAN_HISTORYSEARCH_COOKIE` only if the future live
   probe proves a cookie is required.

After this setup, use the live v2 probe above to decide whether v2 OAuth is the
first viable source path. If v2 returns `payment_required`, `unauthorized`, or
another blocked status, prepare the narrow `historysearch` fallback instead.

See [docs/source-probe-setup.md](docs/source-probe-setup.md) for the detailed
setup contract and safety boundary.
