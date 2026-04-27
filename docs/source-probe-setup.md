# Source Probe Setup

This document defines the handoff between the safe local scaffolding and the
first external Foursquare/Swarm work.

The default `source probe` command is dry config validation only. It does not
call Foursquare, call Swarm, open a browser, refresh tokens, ingest check-ins,
write an evidence database, or validate whether a token/session still works.

The explicit `--live --adapter v2` mode performs one minimal read-only
Foursquare v2 check-in-history request. No other adapter has a live probe yet.

The separate `raw fetch --adapter v2` command preserves one raw response after
the live v2 path has already been proven. It is intentionally conservative: one
request per invocation, small default limit, no pagination loop, and no SQLite
write.

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

## v2 OAuth path

Preferred if the future live probe can read check-in history for the account.

Current Foursquare v2 docs identify the target read endpoint as:

```text
GET https://api.foursquare.com/v2/users/self/checkins
```

The v2 docs require a version parameter and support authenticated user access
with an OAuth access token. The live probe tests this endpoint with a minimal
limit and redacted errors before any ingest/backfill work exists.

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

Julian's external setup steps:

1. Create or identify a Foursquare developer app.
2. Register a local redirect URI for an OAuth web flow.
3. Authorize the intended account, such as `julian`.
4. Exchange the OAuth code for an access token.
5. Put the access token in the environment or in a git-ignored config file.
6. Rerun the dry probe and confirm it reports `ready_for_live_probe`.
7. Run the explicit live v2 command and inspect the redacted JSON status.

Do not paste the token into issues, commits, test fixtures, terminal transcripts
intended for sharing, or docs.

## Swarm web historysearch fallback

Use this only if v2 OAuth is blocked, gated, or does not provide usable
check-in history.

Required for a future live historysearch probe:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_USERID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_WSID
SWARM_CADENCE_JULIAN_HISTORYSEARCH_OAUTH_TOKEN
```

Optional, only if the future live probe proves it is needed:

```text
SWARM_CADENCE_JULIAN_HISTORYSEARCH_COOKIE
```

Julian's external setup steps:

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

Now that the v2 live probe and conservative raw preservation exist, use the
saved raw files to choose the next source slice:

- If live v2 returns `success` with useful field coverage, build the first
  normalized SQLite evidence slice around preserved v2 raw files.
- If live v2 returns `payment_required`, `unauthorized`, or durable `blocked`,
  implement the narrow live `historysearch` fallback.
- Keep export/import available for bootstrap, backfill, and reconciliation.
- Continue to save no fixtures unless they are sanitized and explicitly used in
  tests.

The live probe decides source viability only. It is not ingest/backfill.

## References

- Foursquare v2 `Get User Checkins`: <https://docs.foursquare.com/developer/reference/get-user-checkins>
- Foursquare v2 authentication: <https://docs.foursquare.com/developer/reference/v2-authentication>
