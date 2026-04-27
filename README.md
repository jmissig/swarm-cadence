# swarm-cadence

`swarm-cadence` is a small local-first CLI for preserving and querying
Foursquare Swarm check-in history as private evidence for OpenClaw/Robut.

The first slice is intentionally narrow: it validates local configuration and
can perform one explicit read-only v2 source probe. It does not ingest data,
write an evidence database, or make lunch recommendations.

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
