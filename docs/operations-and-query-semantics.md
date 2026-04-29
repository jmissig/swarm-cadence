# Operations and Query Semantics

This note holds the operator/query detail that should stay out of the top-level README.

## Configuration and accounts

The normal config location is:

```text
~/Library/Application Support/swarm-cadence/config.json
```

`auth login` creates or updates that JSON without hand-editing:

```bash
swarm-cadence auth login      # prompts for account label; default: julian
swarm-cadence auth login --account alice
```

On first run, omitted `--account` defaults to `julian`. When accounts already exist, `auth login` lists them and lets the operator update an existing label or add a new one such as `alice`. It can store a pasted Foursquare v2 access token or perform the documented OAuth code exchange. It never prints tokens or client secrets. `swarm-cadence setup` remains a compatibility alias for `auth login`.

Check auth state without changing files:

```bash
swarm-cadence auth status --account julian
swarm-cadence auth status --account julian --format json
```

Use `config/swarm-cadence.config.example.json` as a template for manual config:

```bash
make install-config-example
```

Keep real tokens out of git. Non-interactive auth login should pass both `--account <label>` and `--access-token <token>`; JSON mode never prompts.

Account labels are explicit and simultaneous. There is no silent Julian/Alice blending. Each account has its own credentials, raw provenance, and SQLite evidence DB.

Named geography presets also live in config. Top-level `geographies.<name>` are shared; `accounts.<account>.geographies.<name>` override shared presets for that account. Supported kinds are:

- `anchor`: `latitude`, `longitude`, optional `default_radius_meters`
- `area`: `localities` with factual locality/region/postal/country selectors

Do not commit real private coordinates.

## Source status and probes

`source status` discovers configured account scopes and local evidence paths without testing credentials or reading evidence:

```bash
swarm-cadence source status --format json
swarm-cadence source status --account julian --format json
```

It reports whether v2/historysearch inputs are present and whether default raw/SQLite paths exist. It does not query SQLite, read raw payloads, call Foursquare, or print tokens/cookies/session values.

Dry probes validate local config shape only:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json
swarm-cadence source probe --account julian --adapter historysearch --format json
```

A live v2 probe is one explicit read-only source viability check:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json --live
```

It performs one `GET /v2/users/self/checkins` request with `limit=1`. It does not ingest, backfill, preserve raw payloads, or write SQLite.

## Raw preservation and ingest

Preserve one raw v2 check-ins page explicitly:

```bash
swarm-cadence raw fetch --account julian --adapter v2 --limit 250 --offset 0
```

`raw fetch` performs exactly one request per invocation. `--limit` defaults to `250` and cannot exceed `250`; `--offset` defaults to `0` and must be non-negative. By default, raw files are written under:

```text
~/Library/Application Support/swarm-cadence/accounts/<account>/raw/v2/checkins
```

The command writes one unmodified `*.raw.json` response and one adjacent redacted `*.manifest.json`. Console output is a compact summary only. `data/` is git-ignored; do not commit raw check-in data.

Use `ingest` for bounded cron-friendly collection:

```bash
swarm-cadence ingest --account julian --adapter v2 --format json
```

Defaults are intentionally small: `--pages 4`, `--limit 250`, and `--delay-ms 1000`. It preserves each raw page and manifest, imports after each successful page, and stops when it reaches an existing local check-in id, a short page, or the page cap. Status values include `updated`, `no_new_checkins`, `updated_partial`, `config_missing`, `source_blocked`, and `import_failed`.

## Offline import and audits

Import preserved v2 raw files into SQLite:

```bash
swarm-cadence db import-raw --account julian
```

The importer performs no network calls. It verifies each raw file against its manifest SHA256, then upserts raw files, check-ins, venues, categories, and check-in/category links.

The default SQLite path is:

```text
~/Library/Application Support/swarm-cadence/accounts/<account>/swarm-cadence.sqlite
```

Import official Foursquare export/takeout files:

```bash
swarm-cadence db import-files --account julian --path "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Robut/Julian/Foursquare" --format json
```

When export rows overlap existing v2/API check-ins by id, the importer preserves the richer API row and inserts only export-only historical rows. It writes `quality/checkins-missing-values.csv` next to the SQLite DB when imported check-ins have null values in expected fields such as `venue`.

Audit raw v2 pages against an official export by check-in id:

```bash
swarm-cadence audit overlap --account julian --path "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Robut/Julian/Foursquare" --format json
```

The audit is read-only and compares preserved source files directly.

## Query semantics

`query categories` lists known category names for an account, ordered by supporting check-ins.

`query venues` returns visit counts, first/last seen timestamps, categories, selected evidence sort, optional inline annotations, and a drill-down descriptor for reproducing supporting visit rows.

`query visits` returns bounded check-in evidence with venue/category labels plus import-time local-time sidecar fields (`local_date`, `local_hour`, `local_weekday_iso`, and timezone evidence) when raw check-ins provided enough information.

`query cadence` adds per-venue descriptive rollups: support counts, first/last seen, days since last visit relative to evidence freshness, distinct local dates, local-hour buckets, ISO weekday buckets, weekday/weekend counts, simple observed gap days, source coverage, and visit drill-down descriptors.

`query compare` compares venue support across broad baseline and recent windows. `query lapses` is a thin active/lapsed wrapper over comparison evidence. Neither command means “disliked,” “abandoned,” or “favorite” without Robut-level interpretation above the evidence.

`query venues`, `query cadence`, and `query compare` accept `--sort nearest|strongest|recent|stale`. With distance filters, the default is `nearest`; without distance filters, `query venues` and `query cadence` default to `strongest`, while `query compare` defaults to `stale`. `--sort nearest` requires `--near-lat`, `--near-lng`, and `--radius-meters`.

## Geography semantics

`query venues`, `query cadence`, and `query compare` can be bounded by factual Foursquare venue location fields (`--locality`, `--region`, `--postal-code`, `--country-code`), named factual areas (`--area <name>`), category names (repeat `--category`, OR semantics), named anchors (`--near-place <name>`), and/or explicit map distance using `--near-lat`, `--near-lng`, and `--radius-meters`.

Place wording matters:

- “in San Mateo” → locality fields such as `--locality "San Mateo" --region CA --country-code US`
- “near San Carlos” → a geographic anchor/radius so nearby Redwood City or Belmont venues can still match
- locality plus radius → AND refinement, not the default meaning of “near”

Named `--near-place` presets expand to visible latitude/longitude/radius filters. Named `--area` presets expand to a visible OR list of factual locality/region/postal/country selectors. Top-level JSON includes `geography.requested`, `geography.resolved`, and `geography.semantics`; nested `filters` show effective primitive filters or `area_localities`.

## Retrospective venue identity

Foursquare venue identity can be retrospective. If a venue is renamed, merged, or otherwise updated upstream, old check-ins may come back from the API with the current venue name/identity rather than the name a human remembers from the time of the visit. Treat venue names as current/source identity evidence, not perfect historical labels.

Use `annotations` to preserve human-known caveats such as “this was the old Bliss Coffee spot, later Red Giant Coffee, now closed.”

## Evidence packets and windows

`evidence window` builds a generic evidence envelope over an explicit date/hour window for an LLM or Almanac layer to interpret. It is a diagnostic/query shape, not a final Robut packet.

`evidence packet` composes venue support and cadence facts over explicit time and geography definitions. It emits `swarm_experimental_packet` with labeled evidence views: `strongest`, `recent`, `stale`, and `nearest` when distance filters are present. It includes source coverage, caveats, nested query results, and drill-down descriptors. It deliberately avoids hidden scoring, recommendation prose, correction state, open-now data, and cross-source joins.

## Date and time filters

Date-only `--from` starts at UTC midnight. Date-only `--to` includes the full UTC day for current instant-bound query filters. Almanac-style calendar/time-of-day filters should use imported local-time fields and treat local check-in calendar/time as the default; UTC/absolute filters should be explicitly named when added.

Fuzzy labels such as “lunch” or “morning” belong to the LLM/Almanac layer choosing explicit windows, not to hidden presets in this evidence CLI.
