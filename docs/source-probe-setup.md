# Source Probe Setup

This document defines the handoff between safe local commands and explicit
external Foursquare/Swarm reads.

The default `source probe` command is dry config validation only. It does not
call Foursquare, call Swarm, open a browser, refresh tokens, ingest check-ins,
write an evidence database, or validate whether a token/session still works.

The explicit `--live --adapter v2` mode performs one minimal read-only
Foursquare v2 check-in-history request. No other adapter has a live probe yet.

The separate `raw fetch --adapter v2` command preserves one raw response after
the live v2 path has already been proven. It is intentionally conservative: one
request per invocation, small default limit, no pagination loop, and no SQLite
write.

The `db import-raw` command is the first SQLite slice. It performs no network
calls; it reads preserved v2 raw/manifest pairs from disk and builds a small
query sidecar.

## Current command

```bash
swift run swarm-cadence source probe --account julian --adapter v2 --format json
swift run swarm-cadence source probe --account julian --adapter historysearch --format json
```

Optional dotenv-style config:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env
```

Environment variables override values from the config file. All configured
values are reported as present or missing only; values are never printed.

## Live v2 command

Run only when a real v2 OAuth token has been stored outside git:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env \
  --live
```

This performs exactly one read-only request:

```text
GET https://api.foursquare.com/v2/users/self/checkins?limit=1&v=<api-version>&oauth_token=<redacted>
```

The command writes no database, saves no fixtures, and does not mutate remote
state. Output reports status and field coverage only. Possible live statuses:

- `success` — the v2 endpoint returned a usable check-ins envelope.
- `unauthorized` — the token was rejected or lacks access.
- `payment_required` — the v2 endpoint appears gated for this app/token.
- `blocked` — another non-success HTTP/API status blocked the probe.
- `schema_unexpected` — the response did not contain the expected check-ins
  shape.
- `network_error` — the request failed before a parseable HTTP response.

On success, JSON includes field coverage for check-in id, `createdAt`, venue
id/name, lat/lng, categories, photos, returned count, total count when present,
and the sample timestamp. Raw payloads are not printed or saved.

## Raw v2 preservation command

Run only after a live v2 source probe succeeds:

```bash
swift run swarm-cadence raw fetch \
  --account julian \
  --adapter v2 \
  --format json \
  --config ./.swarm-cadence.env \
  --out data/raw/v2/checkins \
  --limit 250 \
  --offset 0
```

This performs exactly one read-only request:

```text
GET https://api.foursquare.com/v2/users/self/checkins?limit=<1...250>&offset=<0...>&v=<api-version>&oauth_token=<redacted>
```

Safety boundary:

- default `--limit` is `250`;
- hard max is `250`; larger values fail before any network request;
- default `--offset` is `0`; negative offsets fail before any network request;
- current Get User Checkins docs identify `250` as the endpoint limit, so this
  command uses 250 as the largest documented page size;
- no pagination, cursor, or broad backfill exists in this slice;
- `--out` is required and one raw JSON response is written there;
- raw files are named with a UTC timestamp, adapter, account, check-ins marker,
  offset page marker, and limit;
- an adjacent manifest records endpoint, adapter, account, limit, offset, page
  marker, API version, fetched timestamp, HTTP status, v2 `meta.code` when
  parseable, returned/total counts when parseable, bytes, and SHA256;
- raw response bytes are not altered when written as `*.raw.json`;
- tokens, cookies, OAuth params, and raw payloads are not printed.

Use `data/raw/v2/checkins` for local manual runs. `data/` is git-ignored and
raw check-in payloads must not be committed.

To preserve a deliberate four-page sample of roughly 1000 check-ins, run four
separate invocations:

```bash
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 0
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 250
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 500
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 750
```

This is intentionally manual paging. Each command performs one request only; the
CLI does not follow cursors or loop through pages.

## Offline v2 SQLite import

After preserving one or more raw v2 pages, import them into a local SQLite
sidecar:

```bash
swift run swarm-cadence db import-raw \
  --db data/swarm-cadence.sqlite \
  --raw-dir data/raw/v2/checkins
```

Safety boundary:

- no network request is performed;
- only `*.manifest.json` files and their matching `*.raw.json` files are read;
- raw SHA256 and byte count must match the manifest before a file is imported;
- imported rows keep raw-file provenance through `raw_files.id`;
- reruns are idempotent through upserts on raw relative filename, check-in id,
  venue id, and category id;
- raw files and SQLite files under `data/` remain git-ignored.

The initial schema is intentionally small:

- `raw_files` records file metadata from the manifest: relative filename,
  SHA256, bytes, fetched timestamp, adapter, account, endpoint, API version,
  limit/offset, HTTP/API status, returned/total counts, and import timestamp;
- `checkins` records check-in id, account, adapter, created timestamp, venue id,
  raw file provenance, and the reserialized raw check-in object;
- `venues` records venue id, name, lat/lng, category summary JSON, and raw venue
  JSON;
- `categories` and `checkin_categories` record category labels and check-in
  category provenance when present.

Audit aggregate coverage:

```bash
swift run swarm-cadence db stats --db data/swarm-cadence.sqlite
```

`db stats` reports raw file, check-in, venue, and category counts plus oldest
and latest check-in timestamps. It does not print raw payload contents.

## v2 OAuth path

Primary path for Julian after the successful live v2 probe. Run the same
credential probe for each additional account before fetching or importing that
account's data.

Current Foursquare v2 docs identify the target read endpoint as:

```text
GET https://api.foursquare.com/v2/users/self/checkins
```

The v2 docs require a version parameter and support authenticated user access
with an OAuth access token. The live probe tests this endpoint with a minimal
limit and redacted errors before raw preservation or backfill work for an
account.

Required for a live v2 probe:

```text
SWARM_CADENCE_JULIAN_V2_ACCESS_TOKEN
```

Useful setup breadcrumbs, stored outside git:

```text
SWARM_CADENCE_JULIAN_V2_CLIENT_ID
SWARM_CADENCE_JULIAN_V2_CLIENT_SECRET
SWARM_CADENCE_JULIAN_V2_REDIRECT_URI
```

External setup steps for a new or repaired v2 credential:

1. Create or identify a Foursquare developer app.
2. Register a local redirect URI for an OAuth web flow.
3. Authorize the intended account, such as `julian`.
4. Exchange the OAuth code for an access token.
5. Put the access token in the environment or in a git-ignored config file.
6. Rerun the dry probe and confirm it reports `ready_for_live_probe`.
7. Run the explicit live v2 command and inspect the redacted JSON status before
   any `raw fetch`.

Do not paste the token into issues, commits, test fixtures, terminal transcripts
intended for sharing, or docs.

## Swarm web historysearch fallback

Use this only if v2 OAuth is blocked, gated, or does not provide usable
check-in history for an account.

Required for a future live historysearch probe:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN
```

Optional, only if a future live historysearch probe proves it is needed:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_COOKIE
```

External setup steps for a historysearch fallback credential:

1. Log in to Swarm in a browser for the intended account.
2. Open the browser's network tools.
3. Find a check-in history/historysearch request.
4. Copy only the minimal request parameters needed for a future live probe:
   `userid`, `wsid`, and `oauth_token`.
5. Store those values outside git in the matching
   `SWARM_CADENCE_JULIAN_HISTORYSEARCH_*` inputs.
6. Rerun the dry probe and confirm it reports `ready_for_live_probe`.

Treat these values as browser-session secrets. They are more brittle and more
sensitive than normal app configuration.

## Account labels

The CLI requires an explicit account label:

```bash
--account julian
--account alice
```

The label becomes part of the expected variable name. Hyphens are converted to
underscores and the label is uppercased:

```text
--account julian       -> SWARM_CADENCE_JULIAN_...
--account alice        -> SWARM_CADENCE_ALICE_...
--account test-person  -> SWARM_CADENCE_TEST_PERSON_...
```

Do not use one account's token/session for another account label. Multi-account
work must preserve attribution from the first row onward.

## Next implementation checkpoint

Now that the v2 live probe, conservative raw preservation, and offline SQLite
import exist, use the local sidecar to define the first evidence queries:

- derive venue visit counts and date ranges from imported v2 check-ins;
- add lunch-window filters against stored timestamps;
- keep export/import available for bootstrap, backfill, and reconciliation;
- keep `historysearch` as fallback only if v2 becomes blocked for ongoing use;
- continue to save no fixtures unless they are sanitized and explicitly used in
  tests.

The live probe decides source viability only. It is not ingest/backfill.

## References

- Foursquare v2 `Get User Checkins`: <https://docs.foursquare.com/developer/reference/get-user-checkins>
- Foursquare v2 authentication: <https://docs.foursquare.com/developer/reference/v2-authentication>
