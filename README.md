# swarm-cadence

`swarm-cadence` is a small local-first CLI for preserving and querying
Foursquare Swarm check-in history as private evidence for OpenClaw/Robut.

It currently supports:

- source/account readiness discovery without network or payload reads;
- explicit source probes for Foursquare v2 and Swarm web `historysearch` config;
- cron-friendly bounded v2 ingest updates that preserve raw pages and import them locally;
- one-request and explicit multi-page raw v2 check-in response preservation;
- offline SQLite import from preserved raw v2 files and Foursquare export files;
- aggregate database stats and source overlap audits;
- evidence queries for venues, visits, local calendar windows, venue cadence comparisons, and geography filters.

It does not make recommendations, run hidden background sync, write to
Foursquare/Swarm, or inspect raw payloads during routine commands.

## Build and Test

```bash
make build
make test
```

The direct SwiftPM equivalents are:

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


## Version

`VERSION` is the stable human/tool version contract. Build, release, and test
targets run `make sync-version`, which copies `VERSION` into the compiled CLI
constant used by:

```bash
swift run swarm-cadence --version
```

The same version appears in top-level help and evidence packet provenance as
`tool_version`.

## Configuration

The normal config location is:

```text
~/Library/Application Support/swarm-cadence/config.json
```

The guided first-run auth path creates or updates that JSON config without
requiring hand-editing:

```bash
swift run swarm-cadence auth login      # prompts for account label; default: julian
swift run swarm-cadence auth login --account alice
```

`auth login` prompts for an account label when `--account` is omitted. On the
first run it defaults to `julian`; when accounts already exist, it lists them
and lets you type an existing label to update or a new label such as `alice` to
add a second account. It then prompts for either an existing Foursquare v2
access token or the OAuth client id/secret, redirect URI, and authorization code
needed to exchange for one. The fastest practical path follows the same pattern
other Swarm tools use: copy an `oauth_token` from a Foursquare API Explorer
request and paste it as the access token. The official fallback is the
documented web OAuth code exchange; `auth login` prints the authorization URL,
stores the resulting token under the selected account, and never prints tokens
or client secrets. If a token is already stored, rerunning `auth login` keeps it
unless `--access-token` is supplied. `swarm-cadence setup` remains as a
compatibility alias for `auth login`.

Check auth state without changing files:

```bash
swift run swarm-cadence auth status --account julian
swift run swarm-cadence auth status --account julian --format json
```

Use `config/swarm-cadence.config.example.json` as a template when you prefer
manual config:

```bash
make install-config-example
```

Keep real tokens out of git. `--config <path>` remains available for explicit
repo-local/temp/sandbox runs. Non-interactive auth login should pass both `--account <label>` and
`--access-token <token>`; JSON mode never prompts.

Account labels are explicit and simultaneous:

```bash
--account julian
--account alice
```

The config has separate `accounts.julian` and `accounts.alice` sections. Each
account has its own v2/historysearch credentials, raw provenance, and imported
SQLite rows. Joint/family queries should be explicitly scoped; there is no silent
Julian/Alice blending.

## Source Status

Use source status to discover configured account scopes and local evidence paths
without testing credentials or reading evidence:

```bash
swift run swarm-cadence source status --format json
swift run swarm-cadence source status --account julian --format json
```

`source status` succeeds even when the config file is missing or has no accounts;
in that case it returns an empty account list. For each account it reports
whether v2 and `historysearch` inputs are present, whether the default raw v2
directory and SQLite DB path exist, and whether local evidence appears available
from those paths. It does not query SQLite, read raw payloads, call Foursquare,
or print tokens/cookies/session values.

## Source Probe

Dry source probes validate local config shape only:

```bash
swift run swarm-cadence source probe --account julian --adapter v2 --format json
swift run swarm-cadence source probe --account alice --adapter v2 --format json
swift run swarm-cadence source probe --account julian --adapter historysearch --format json
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
  --limit 250 \
  --offset 0
```

`raw fetch` performs exactly one request per invocation. `--limit` defaults to
`250` and cannot exceed `250`; `--offset` defaults to `0` and must be
non-negative. By default, raw files are written under:

```text
~/Library/Application Support/swarm-cadence/accounts/<account>/raw/v2/checkins
```

Use `--out` to override that path for tests, samples, or one-off runs.

The command writes one unmodified `*.raw.json` response and one adjacent
redacted `*.manifest.json`. Console output is a compact summary only. `data/`
is git-ignored; do not commit raw check-in data.

## Unattended v2 Update

Use `ingest update` for a bounded cron-friendly collection run:

```bash
swift run swarm-cadence ingest update \
  --account julian \
  --adapter v2 \
  --format json
```

Defaults are intentionally small: `--pages 4`, `--limit 250`, and
`--delay-ms 1000`. The command performs v2 read-only check-ins requests,
preserves each raw page and manifest, imports after each successful page, and
stops when it reaches an existing local check-in id, a short page, or the page
cap. Status values include `updated`, `no_new_checkins`, `updated_partial`,
`config_missing`, `source_blocked`, and `import_failed`.

Use explicit paths for tests and one-off dry runs:

```bash
swift run swarm-cadence ingest update \
  --account alice \
  --adapter v2 \
  --raw-dir /tmp/swarm-cadence/alice/raw \
  --db /tmp/swarm-cadence/alice/swarm-cadence.sqlite \
  --pages 1 \
  --delay-ms 0 \
  --format json
```

## Offline SQLite Import

Import preserved v2 raw files into a rebuildable local SQLite sidecar:

```bash
swift run swarm-cadence db import-raw --account julian
```

The importer performs no network calls. It verifies each raw file against its
manifest SHA256, then upserts aggregate evidence tables for raw files,
check-ins, venues, categories, and check-in/category links.

The default SQLite path is:

```text
~/Library/Application Support/swarm-cadence/accounts/<account>/swarm-cadence.sqlite
```

Use `--db` and `--raw-dir` to override paths for tests, samples, or one-off runs. Repeat import/stats with `--account alice` for Alice's parallel evidence store.

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

Audit aggregate coverage:

```bash
swift run swarm-cadence db stats --account julian
swift run swarm-cadence db stats --account julian --format json
```

`db stats` reports aggregate counts plus factual freshness: last raw fetch time,
last import time, oldest/latest check-in timestamps, and `current_through` as
the latest imported check-in timestamp. It does not print raw payload contents.

## Evidence Queries

Query aggregate venue support from the per-account SQLite sidecar:

```bash
swift run swarm-cadence query categories --account julian --format json
swift run swarm-cadence query venues --account julian --format json
swift run swarm-cadence query venues --account julian --from 2024-01-01 --to 2024-12-31 --limit 50
swift run swarm-cadence query venues --account julian --sort strongest --format json
swift run swarm-cadence query venues --account julian --sort recent --format json

# "in San Mateo" — factual Foursquare venue locality fields
swift run swarm-cadence query venues --account julian --locality "San Mateo" --region CA --country-code US --format json

# "near San Carlos" — geometry around an anchor, allowing nearby cities too
swift run swarm-cadence query venues --account julian --near-lat 37.5072 --near-lng -122.2605 --radius-meters 7000 --format json

# narrow/refine when intended: locality AND distance
swift run swarm-cadence query venues --account julian --locality "San Mateo" --near-lat 37.563 --near-lng -122.325 --radius-meters 5000 --format json
```

Query supporting visits, optionally drilled down to one venue:

```bash
swift run swarm-cadence query visits --account julian --venue-id <venue-id> --format json
```

Use local-calendar filters for Almanac-style questions. These read import-time
sidecar fields; they do not recalculate timezones at query time:

```bash
swift run swarm-cadence query visits --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
swift run swarm-cadence query venues --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
```

Compare venue support across a broad baseline and a recent window. This is the
reusable cadence query for questions like active anchors, lapsed places, and
rotation changes; interpretation belongs above the CLI:

```bash
swift run swarm-cadence query compare --account julian --baseline-from 2024-01-01 --recent-from 2026-01-01 --hour-from 11 --hour-to 14 --locality "San Mateo" --region CA --format json
swift run swarm-cadence query compare --account julian --baseline-from 2024-01-01 --recent-from 2026-01-01 --sort stale --format json
swift run swarm-cadence query compare --account julian --baseline-from 2024-01-01 --recent-from 2026-01-01 --sort recent --format json
```

Build a generic evidence envelope over an explicit date/hour window for an LLM or
Almanac layer to interpret. This is a diagnostic/query shape, not a final Robut packet:

```bash
swift run swarm-cadence evidence window --account julian --date 2025-12-23 --hour-from 8 --hour-to 11 --format json
```

Build a first experimental evidence envelope by composing existing venue support
and cadence facts over explicit time and geography definitions. This is a
query diagnostic / source-piece composition, not a recommendation and not the final Robut packet:

```bash
swift run swarm-cadence evidence packet \
  --account julian \
  --date 2026-04-27 \
  --hour-from 11 \
  --hour-to 14 \
  --near-lat 37.5072 \
  --near-lng -122.2605 \
  --radius-meters 7000 \
  --category "Mexican Restaurant" \
  --category "Pizzeria" \
  --category "Sandwich Spot" \
  --baseline-from 2024-01-01 \
  --recent-from 2026-01-01 \
  --format json
```

`query categories` lists the known category names for an account, ordered by
supporting check-ins. `query venues` returns visit counts, first/last seen
timestamps, categories, the selected evidence sort, and a drill-down descriptor
for reproducing the supporting visit rows. `query venues` and `query compare`
accept `--sort nearest|strongest|recent|stale` and include the effective sort
and order label in JSON and human output. With distance filters, the default is
`nearest`; without distance filters, `query venues` defaults to `strongest` and
`query compare` defaults to `stale`, preserving the earlier effective ordering
while making it explicit. `--sort nearest` requires `--near-lat`, `--near-lng`,
and `--radius-meters`.

`query venues` and `query compare` can also be bounded by factual Foursquare venue location
fields (`--locality`, `--region`, `--postal-code`, `--country-code`), category
names (repeat `--category`, OR semantics), and/or explicit map distance using
`--near-lat`, `--near-lng`, and `--radius-meters`.
The distance options must be used together, and matching rows include
`distance_meters` as evidence.

Place wording matters: use locality fields for **“in San Mateo”** style queries.
For **“near San Carlos”**, use a geographic anchor/radius so nearby Redwood City
or Belmont venues can still match. Combining locality and radius is an AND
refinement, not the default meaning of “near.” Future `--near-place`/`--area`
work should make that anchor resolution inspectable instead of hiding it.

`evidence packet` is an experimental evidence envelope, not a durable public
API contract and not the final Robut-composed packet. It emits `swarm_experimental_packet` with labeled evidence views
over the same explicit filters: `strongest`, `recent`, `stale`, and `nearest`
when distance filters are present. Each view contains venue support and cadence
comparison facts ordered by that label. It includes the target window, explicit
geography semantics, source coverage, nested query results, sources, caveats, and
drill-down descriptors. It deliberately avoids hidden scoring, recommendation prose,
correction state, open-now data, and cross-source joins.

`query visits`
returns bounded check-in evidence with venue/category labels plus import-time
local-time sidecar fields (`local_date`, `local_hour`, `local_weekday_iso`, and
timezone evidence) when the raw check-in provided enough information. Both
commands open an existing SQLite DB read-only, default to the account's own DB,
and do not print raw payloads. Date-only `--from` starts at UTC midnight;
date-only `--to` includes the full UTC day for these first instant-bound query
filters. Almanac-style calendar/time-of-day filters should use the imported
local-time fields and should treat local check-in calendar/time as the default;
UTC/absolute filters should be explicitly named when added. Fuzzy labels such as
“lunch” or “morning” belong to the LLM/Almanac layer choosing explicit windows,
not to hidden presets in this evidence CLI.

## Safety Boundaries

- Keep tokens, cookies, browser-session details, raw payloads, and SQLite files
  out of git.
- Use explicit `--account` for non-login commands; `auth login` can prompt for it in human mode. Use `--config`, `--db`, `--raw-dir`, and `--out` when overriding defaults.
- Default paths live under `~/Library/Application Support/swarm-cadence`, not dotfiles.
- Do not run `--live` or `raw fetch` as routine tests.
- Do not use one account's credentials for another account label.
- Treat the SQLite DB as rebuildable from preserved raw evidence.
- Prefer `--format json` for scripts and agents; `--json` is accepted as a
  shorthand where supported.

Detailed source setup and schema notes live in
[docs/source-probe-setup.md](docs/source-probe-setup.md). Pattern-intelligence
direction lives in
[docs/pattern-intelligence-proposal.md](docs/pattern-intelligence-proposal.md).
