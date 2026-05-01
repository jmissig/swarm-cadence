# Read-Only SQLite Exploration

This guide is for trusted LLM/tool work that needs to inspect a
`swarm-cadence` SQLite evidence database faster than the stable CLI verbs allow.
Treat this as a Datasette-style microscope: useful for source coverage,
schema/debugging, and question discovery, but not the normal conversational
contract.

Use the stable CLI first when it answers the question:

```bash
swarm-cadence db stats --account <account> --format json
swarm-cadence query categories --account <account> --format json
swarm-cadence query venues --account <account> --format json
swarm-cadence query visits --account <account> --venue-id <venue-id> --format json
swarm-cadence query cadence --account <account> --venue-id <venue-id> --format json
swarm-cadence query compare --account <account> --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
```

Drop to SQL only when you need to answer questions such as:

- Is a missing result caused by source coverage, import shape, or filters?
- Which categories or venue fields are sparse?
- Are local-time sidecar fields present enough for a date/hour analysis?
- What query shape should become a future CLI verb?
- Which rows support or contradict an LLM-composed Almanac/Guide claim?

Do not use ad hoc SQL to mutate evidence, create durable interpretation, or
replace the stable CLI verbs in normal answers.

## Open The Database Safely

Default account DB path:

```text
~/Library/Application Support/swarm-cadence/accounts/<account>/swarm-cadence.sqlite
```

Prefer an explicit DB path supplied by the human or discovered via
`swarm-cadence source status --format json`. Keep account scope explicit.

For `sqlite3`, open read-only and turn on query-only mode before inspecting:

```bash
DB="$HOME/Library/Application Support/swarm-cadence/accounts/<account>/swarm-cadence.sqlite"
sqlite3 -readonly "$DB"
```

Inside SQLite:

```sql
.headers on
.mode box
.timer on
PRAGMA query_only = ON;
PRAGMA database_list;
```

For a one-off shell query:

```bash
sqlite3 -readonly "$DB" <<'SQL'
PRAGMA query_only = ON;
SELECT name, type
FROM sqlite_master
WHERE type IN ('table', 'view')
ORDER BY type, name;
SQL
```

If Datasette is installed, use it as a local read-only browser:

```bash
datasette --immutable "$DB"
```

Do not start a public server for private location history. Bind to localhost if
you need to pass explicit host/port flags.

## Hard Boundaries

Allowed:

- `SELECT`, `WITH`, scalar functions, joins, grouping, `ORDER BY`, `LIMIT`;
- `PRAGMA table_info(...)`, `PRAGMA index_list(...)`, `PRAGMA database_list`;
- exporting small, redacted aggregate results to repo-local scratch when needed.

Avoid by default:

- selecting `raw_json` from `checkins` or `venues`;
- printing raw payloads, shouts, token-like fields, or large location trails;
- blending accounts in one result unless the user explicitly asked for a
  multi-account comparison and the output keeps account labels visible.

Never run:

- `INSERT`, `UPDATE`, `DELETE`, `REPLACE`, `CREATE`, `DROP`, `ALTER`;
- `VACUUM`, `REINDEX`, `ANALYZE`, `PRAGMA writable_schema`, or writable
  `ATTACH`;
- `swarm-cadence ingest`, `db import-*`, `db migrate`, or `annotations add`
  during read-only exploration.

If a query reveals an interpretation that should change future answers, ask the
human before creating an annotation through the normal CLI.

## Current Evidence Tables

The base evidence DB is intentionally small and rebuildable from raw files:

- `raw_files`: preserved source-file manifests, source adapter, account, fetch
  and import metadata, offsets, status, counts, and SHA256;
- `checkins`: check-in id, account, source adapter, UTC timestamp, local-time
  sidecar fields, venue id, raw-file provenance, import timestamp, and raw JSON;
- `venues`: source venue id, name, coordinates, factual location fields,
  category summary JSON, raw venue JSON, and update timestamp;
- `categories`: Foursquare category ids and labels;
- `checkin_categories`: check-in/category join rows with account and raw-file
  provenance;
- `annotations`: human-readable interpretive notes attached to targets such as
  venues, check-ins, categories, geography, windows, or context.

Inspect the live schema before writing a query; migrations may add columns:

```sql
SELECT identifier
FROM grdb_migrations
ORDER BY identifier;

PRAGMA table_info(checkins);
PRAGMA table_info(venues);
PRAGMA table_info(raw_files);
PRAGMA table_info(categories);
PRAGMA table_info(checkin_categories);
PRAGMA table_info(annotations);
```

## Coverage Queries

Set the account once per query with a CTE so examples stay copyable:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  c.account,
  COUNT(*) AS checkins,
  COUNT(DISTINCT c.venue_id) AS venues,
  MIN(c.created_at_iso) AS oldest_utc,
  MAX(c.created_at_iso) AS latest_utc,
  MIN(c.local_date) AS oldest_local_date,
  MAX(c.local_date) AS latest_local_date,
  MAX(c.imported_at) AS last_imported_at
FROM checkins c, params p
WHERE c.account = p.account
GROUP BY c.account;
```

Raw source coverage:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  rf.account,
  rf.adapter,
  COUNT(*) AS raw_files,
  MIN(rf.fetched_at) AS first_fetched_at,
  MAX(rf.fetched_at) AS last_fetched_at,
  SUM(COALESCE(rf.returned_count, 0)) AS source_items_returned,
  MAX(rf.total_count) AS latest_source_total_count,
  MAX(rf.imported_at) AS last_imported_at
FROM raw_files rf, params p
WHERE rf.account = p.account
GROUP BY rf.account, rf.adapter
ORDER BY rf.adapter;
```

Source mix in imported check-ins:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  c.account,
  c.source_adapter,
  COUNT(*) AS checkins,
  MIN(c.created_at_iso) AS oldest_utc,
  MAX(c.created_at_iso) AS latest_utc
FROM checkins c, params p
WHERE c.account = p.account
GROUP BY c.account, c.source_adapter
ORDER BY checkins DESC;
```

Local-time completeness:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  COUNT(*) AS checkins,
  SUM(CASE WHEN local_date IS NULL THEN 1 ELSE 0 END) AS missing_local_date,
  SUM(CASE WHEN local_hour IS NULL THEN 1 ELSE 0 END) AS missing_local_hour,
  SUM(CASE WHEN local_weekday_iso IS NULL THEN 1 ELSE 0 END) AS missing_local_weekday,
  SUM(CASE WHEN local_timezone_id IS NULL THEN 1 ELSE 0 END) AS missing_timezone_id
FROM checkins c, params p
WHERE c.account = p.account;
```

Venue and coordinate completeness:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  COUNT(*) AS checkins,
  SUM(CASE WHEN c.venue_id IS NULL THEN 1 ELSE 0 END) AS missing_venue_id,
  SUM(CASE WHEN v.venue_id IS NULL AND c.venue_id IS NOT NULL THEN 1 ELSE 0 END) AS missing_venue_row,
  SUM(CASE WHEN v.lat IS NULL OR v.lng IS NULL THEN 1 ELSE 0 END) AS missing_coordinates,
  SUM(CASE WHEN v.locality IS NULL THEN 1 ELSE 0 END) AS missing_locality
FROM checkins c
LEFT JOIN venues v ON v.venue_id = c.venue_id
JOIN params p ON c.account = p.account;
```

Category completeness by check-in:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  COUNT(*) AS checkins,
  SUM(
    CASE WHEN EXISTS (
      SELECT 1
      FROM checkin_categories cc
      WHERE cc.checkin_id = c.checkin_id
        AND cc.account = c.account
    ) THEN 1 ELSE 0 END
  ) AS checkins_with_categories,
  SUM(
    CASE WHEN NOT EXISTS (
      SELECT 1
      FROM checkin_categories cc
      WHERE cc.checkin_id = c.checkin_id
        AND cc.account = c.account
    ) THEN 1 ELSE 0 END
  ) AS checkins_without_categories
FROM checkins c, params p
WHERE c.account = p.account;
```

## Venue, Category, And Time Inspection

Top venues by support:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  v.venue_id,
  v.name,
  v.locality,
  v.region,
  v.country_code,
  COUNT(*) AS visits,
  MIN(c.local_date) AS first_local_date,
  MAX(c.local_date) AS last_local_date
FROM checkins c
JOIN venues v ON v.venue_id = c.venue_id
JOIN params p ON c.account = p.account
GROUP BY v.venue_id, v.name, v.locality, v.region, v.country_code
ORDER BY visits DESC, last_local_date DESC
LIMIT 25;
```

Top categories:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  cat.name,
  COUNT(DISTINCT c.checkin_id) AS checkins,
  COUNT(DISTINCT c.venue_id) AS venues,
  MIN(c.local_date) AS first_local_date,
  MAX(c.local_date) AS last_local_date
FROM checkins c
JOIN checkin_categories cc ON cc.checkin_id = c.checkin_id
JOIN categories cat ON cat.category_id = cc.category_id
JOIN params p ON c.account = p.account
WHERE cc.account = c.account
GROUP BY cat.category_id, cat.name
ORDER BY checkins DESC, venues DESC, cat.name
LIMIT 50;
```

Local hour and weekday distribution:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  local_weekday_iso,
  local_hour,
  COUNT(*) AS checkins,
  COUNT(DISTINCT venue_id) AS venues
FROM checkins c, params p
WHERE c.account = p.account
  AND local_weekday_iso IS NOT NULL
  AND local_hour IS NOT NULL
GROUP BY local_weekday_iso, local_hour
ORDER BY local_weekday_iso, local_hour;
```

Venue support in an explicit local window:

```sql
WITH params(account, date_from, date_to, hour_from, hour_to) AS (
  VALUES ('<account>', '2026-01-01', '2026-05-01', 11, 14)
)
SELECT
  v.venue_id,
  v.name,
  v.locality,
  COUNT(*) AS visits,
  MIN(c.local_date) AS first_local_date,
  MAX(c.local_date) AS last_local_date
FROM checkins c
JOIN venues v ON v.venue_id = c.venue_id
JOIN params p ON c.account = p.account
WHERE c.local_date BETWEEN p.date_from AND p.date_to
  AND c.local_hour >= p.hour_from
  AND c.local_hour < p.hour_to
GROUP BY v.venue_id, v.name, v.locality
ORDER BY visits DESC, last_local_date DESC
LIMIT 25;
```

Category support in a factual locality:

```sql
WITH params(account, locality, region) AS (
  VALUES ('<account>', '<locality>', '<region>')
)
SELECT
  cat.name AS category,
  COUNT(DISTINCT c.checkin_id) AS checkins,
  COUNT(DISTINCT c.venue_id) AS venues,
  MAX(c.local_date) AS last_local_date
FROM checkins c
JOIN venues v ON v.venue_id = c.venue_id
JOIN checkin_categories cc ON cc.checkin_id = c.checkin_id
JOIN categories cat ON cat.category_id = cc.category_id
JOIN params p ON c.account = p.account
WHERE cc.account = c.account
  AND v.locality = p.locality
  AND v.region = p.region
GROUP BY cat.category_id, cat.name
ORDER BY checkins DESC, venues DESC, category
LIMIT 50;
```

Recent supporting visits for a venue, without raw payloads:

```sql
WITH params(account, venue_id) AS (
  VALUES ('<account>', '<venue-id>')
)
SELECT
  c.checkin_id,
  c.created_at_iso,
  c.local_created_at,
  c.local_date,
  c.local_hour,
  c.local_weekday_iso,
  v.name,
  v.locality,
  v.region,
  rf.adapter,
  rf.raw_file_name
FROM checkins c
JOIN venues v ON v.venue_id = c.venue_id
JOIN raw_files rf ON rf.id = c.raw_file_id
JOIN params p ON c.account = p.account
WHERE c.venue_id = p.venue_id
ORDER BY c.created_at_unix DESC
LIMIT 50;
```

Annotation targets that may affect interpretation:

```sql
WITH params(account) AS (VALUES ('<account>'))
SELECT
  target_kind,
  target_id,
  COUNT(*) AS annotations,
  MAX(updated_at) AS last_updated_at
FROM annotations a, params p
WHERE a.account = p.account
GROUP BY target_kind, target_id
ORDER BY last_updated_at DESC
LIMIT 50;
```

## Interpreting Results

Keep the LLM answer grounded and narrow:

- report the account, DB path or source status, and freshness dates used;
- distinguish factual locality filters from nearby anchor/radius semantics;
- describe support counts, first/last dates, gaps, and category coverage as
  evidence, not as preference truth;
- mention if raw/API/export coverage, category coverage, local-time fields, or
  annotations limit confidence;
- turn useful query discoveries into proposed CLI improvements instead of
  making ad hoc SQL the durable user-facing surface.

Good close-out shape:

```text
I inspected the local SQLite evidence read-only. The database has coverage
through <date>; category coverage is present for <n>/<total> check-ins in this
scope. The venue/category rows support <finding>, but this is visit-history
evidence only, not open-now or preference proof.
```
