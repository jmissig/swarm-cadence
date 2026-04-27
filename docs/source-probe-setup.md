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
swift run swarm-cadence auth login
swift run swarm-cadence auth status --account julian --format json
swift run swarm-cadence source probe --account julian --adapter v2 --format json
swift run swarm-cadence source probe --account julian --adapter historysearch --format json
```

Default config:

```text
~/Library/Application Support/swarm-cadence/config.json
```

Use `swarm-cadence auth login` for the normal first-run auth path. If
`--account` is omitted in human mode, it prompts for an account label: default
`julian` when no accounts exist, or an existing/new label when accounts are
already present. It creates or merges the JSON config, preserving other accounts
and fallback adapter sections. `swarm-cadence setup` is kept only as a
compatibility alias for `auth login`, so the command shape stays aligned with
`protect-cadence auth login/status/clear`. Use
`config/swarm-cadence.config.example.json` as the manual
template, or run `make install-config-example` to copy it into the default
location without overwriting an existing config.

The JSON config is account-structured with first-class `accounts.julian` and
`accounts.alice` sections. Environment variables override values from the config
file. All configured values are reported as present or missing only; values are
never printed.

`auth login` supports two v2 paths:

- paste an existing access token. This intentionally mirrors the practical path
  used by `liskin/foursquare-swarm-ical`: use Foursquare's API Explorer, grant
  account access, inspect an executed request in DevTools, and copy the
  `oauth_token` query parameter;
- enter the Foursquare OAuth code-flow pieces. The CLI prints
  `https://foursquare.com/oauth2/authenticate?...`, asks for the returned code,
  and exchanges it through the documented `oauth2/access_token` endpoint using
  injectable HTTP transport in tests.

Rerunning `auth login` keeps an already stored token by default, which matches
the local-first/idempotent shape from `protect-cadence` auth setup. Pass
`--account` to skip the label prompt, `--access-token` to replace the token, or
use `auth clear --force` to remove v2 credentials while preserving sibling
account/historysearch config.

`auth status` reports config path/existence, account, v2 token/client
id/client secret/redirect URI presence, default raw and SQLite paths, and the
next suggested command. It does not create files or call the network.

## Live v2 command

Run only when a real v2 OAuth token has been stored outside git:

```bash
swift run swarm-cadence source probe \
  --account julian \
  --adapter v2 \
  --format json \
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
- `--out` is optional; by default one raw JSON response is written under `~/Library/Application Support/swarm-cadence/accounts/<account>/raw/v2/checkins`;
- raw files are named with a UTC timestamp, adapter, account, check-ins marker,
  offset page marker, and limit;
- an adjacent manifest records endpoint, adapter, account, limit, offset, page
  marker, API version, fetched timestamp, HTTP status, v2 `meta.code` when
  parseable, returned/total counts when parseable, bytes, and SHA256;
- raw response bytes are not altered when written as `*.raw.json`;
- tokens, cookies, OAuth params, and raw payloads are not printed.

Use explicit `--out` paths for repo-local/manual samples. Each account has its own default raw archive under `accounts/<label>/`; account labels are also preserved in filenames, manifests, and imported evidence rows.

To preserve a deliberate four-page sample of roughly 1000 check-ins, run four
separate invocations:

```bash
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --limit 250 --offset 0
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --limit 250 --offset 250
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --limit 250 --offset 500
swift run swarm-cadence raw fetch --account julian --adapter v2 --format json --limit 250 --offset 750
```

This is intentionally manual paging. Each command performs one request only; the
CLI does not follow cursors or loop through pages.

## Offline v2 SQLite import

After preserving one or more raw v2 pages, import them into that account's local SQLite sidecar:

```bash
swift run swarm-cadence db import-raw --account julian
```

Safety boundary:

- no network request is performed;
- only `*.manifest.json` files and their matching `*.raw.json` files are read;
- raw SHA256 and byte count must match the manifest before a file is imported;
- imported rows keep raw-file provenance through `raw_files.id`;
- reruns are idempotent through upserts on raw relative filename, check-in id,
  venue id, and category id;
- raw files and SQLite files remain local-only and must not be committed; use explicit repo-local paths only for samples/tests.

Import local file-based sources with `db import-files`. The default source is
`foursquare-export`, which expects a Foursquare export/takeout directory with
`checkins*.json` files:

```bash
swift run swarm-cadence db import-files --account julian --path "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Robut/Julian/Foursquare" --format json
```

When export rows overlap existing v2/API check-ins by id, the importer preserves
the existing richer API row and inserts only export-only historical rows. It also
writes `quality/checkins-missing-values.csv` next to the SQLite DB when imported
check-ins have null values in fields the importer expects, such as `venue`.

Audit raw v2 pages against an official export by check-in id:

```bash
swift run swarm-cadence audit overlap --account julian --path "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Robut/Julian/Foursquare" --format json
```

The audit is read-only and compares preserved source files directly; it does not
write to SQLite or call the network.

The initial schema is intentionally small:

- `raw_files` records file metadata from the manifest: relative filename,
  SHA256, bytes, fetched timestamp, adapter, account, endpoint, API version,
  limit/offset, HTTP/API status, returned/total counts, and import timestamp;
- `checkins` records check-in id, account, adapter, UTC created timestamp,
  import-time local-time sidecar fields when raw timezone evidence is available
  (`local_date`, `local_hour`, `local_weekday_iso`, timezone id/offset), venue
  id, raw file provenance, and the reserialized raw check-in object;
- `venues` records venue id, name, lat/lng, category summary JSON, and raw venue
  JSON;
- `categories` and `checkin_categories` record category labels and check-in
  category provenance when present.

Audit aggregate coverage:

```bash
swift run swarm-cadence db stats --account julian
```

`db stats` reports raw file, check-in, venue, and category counts plus oldest
and latest check-in timestamps. It does not print raw payload contents.

Read aggregate venue evidence from the account DB:

```bash
swift run swarm-cadence query venues --account julian --format json
swift run swarm-cadence query venues --account julian --from 2024-01-01 --to 2024-12-31 --limit 50
swift run swarm-cadence query venues --account julian --locality "San Mateo" --region CA --country-code US --format json
swift run swarm-cadence query venues --account julian --locality "San Mateo" --near-lat 37.563 --near-lng -122.325 --radius-meters 5000 --format json
```

Drill into supporting rows without printing raw payloads:

```bash
swift run swarm-cadence query visits --account julian --venue-id <venue-id> --format json
```

For Almanac-style local calendar/time questions, filter with the imported
sidecar fields:

```bash
swift run swarm-cadence query visits --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
swift run swarm-cadence query venues --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
```

For generic cadence comparison, compare a baseline window against a recent
window. This returns venue-level support facts rather than recommendations:

```bash
swift run swarm-cadence query compare --account julian --baseline-from 2024-01-01 --recent-from 2026-01-01 --hour-from 11 --hour-to 14 --locality "San Mateo" --region CA --format json
```

For builder-facing packets, use the same explicit window without adding fuzzy
labels inside the CLI:

```bash
swift run swarm-cadence evidence window --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
```

`query venues` and `query compare` support factual Foursquare venue-location
bounds with `--locality`, `--region`, `--postal-code`, and `--country-code`, plus
optional explicit map-distance bounds with `--near-lat`, `--near-lng`, and
`--radius-meters`. The distance options must be supplied together, and results
include `distance_meters` as factual evidence rather than a hidden recommendation
or place-name judgment.

Date bounds accept Unix timestamps, ISO8601 instants, or `YYYY-MM-DD` UTC dates.
Date-only `--from` starts at UTC midnight; date-only `--to` includes the full UTC
day for these first instant-bound filters. Almanac-style calendar/time-of-day
filters should use the imported local-time sidecar fields by default; UTC or
absolute-time variants should be explicitly named when added. The query commands
open an existing SQLite DB read-only and fail before creating a DB if import has
not run yet. JSON output includes the account, DB path, normalized bounds,
match/return counts, categories when present, and local-time fields for visits.

## v2 OAuth path

Primary path for Julian after the successful live v2 probe. Alice is a first-class simultaneous account for this tool: run the same credential probe for Alice before fetching or importing Alice's data.

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

1. Try the practical API Explorer path first when available: authorize the
   intended account, inspect an executed request in browser DevTools, and copy
   the `oauth_token` query parameter into `swarm-cadence auth login`.
2. If the API Explorer path is not available, create or identify a Foursquare
   developer app.
3. Register the default local redirect URI or another redirect URI you can copy
   a `code` from: `http://localhost:17342/foursquare/callback`.
4. Run `swarm-cadence auth login`, confirm or enter the account label, leave the access-token prompt
   blank, open the printed authorization URL, and paste the returned code.
5. Confirm `auth status` reports a v2 token present for the correct account.
6. Run the explicit live v2 command and inspect the redacted JSON status before
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
- keep export/import available for audit, reconciliation, and API-missing coordinate breadcrumbs;
- keep `historysearch` as fallback only if v2 becomes blocked for ongoing use;
- continue to save no fixtures unless they are sanitized and explicitly used in
  tests.

The live probe decides source viability only. It is not ingest/backfill.

## References

- Foursquare v2 `Get User Checkins`: <https://docs.foursquare.com/developer/reference/get-user-checkins>
- Foursquare v2 authentication: <https://docs.foursquare.com/developer/reference/v2-authentication>
- `liskin/foursquare-swarm-ical` setup notes: <https://github.com/liskin/foursquare-swarm-ical>
- Aaron Parecki `Swarm-Checkins-Import`/OwnYourSwarm auth notes: <https://github.com/aaronpk/Swarm-Checkins-Import>
- Swarm web `historysearch` DevTools fallback gist: <https://gist.github.com/jsundram/7d8d4fcb5c5684617f4d496dc8c47347>
