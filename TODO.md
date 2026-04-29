# TODO.md — swarm-cadence

Active backlog and critical path only. Durable architecture and constraints live
in `AGENTS.md`; operator usage lives in `README.md`; source/probe contracts live
in `docs/`.

## Critical path

The goal is not to polish isolated query shapes. The goal is to get from local
Swarm evidence to useful, inspectable Almanac/Guide experiments as quickly and
safely as possible.

1. **Establish the raw evidence substrate**
   - Fetch v2 API pages explicitly at `limit=250` to prove the live source,
     preserve raw responses, and capture rich venue/category fields.
   - Build/finish the SQLite schema and raw-file manifest index so every raw
     file imported later has source provenance, account, adapter, fetched/export
     metadata, SHA, byte count, and import status.
   - Import API raw files into SQLite as the preferred row source where present.

2. **Use export/takeout as audit and completeness backstop**
   - Add official export/takeout import as a second raw source.
   - Compare API data vs export data by check-in id to audit completeness and
     field differences.
   - Preserve export-only rows as historical coordinate/timestamp breadcrumbs,
     but prefer richer v2/API rows for overlapping check-in ids.

3. **Run first real evidence reads**
   - Run `db stats` to inspect coverage: raw files, checkins, venues,
     categories, oldest/latest timestamps.
   - Run `query venues`, `query visits`, `query cadence`, and `query compare` against real
     imported data.
   - Capture what is missing before adding more cleverness: stale venues,
     category gaps, duplicate/renamed venues, sparse history, timezone gaps,
     bad support counts, etc.

4. **Use geography constraints in real evidence reads**
   - Existing low-level query support includes factual venue location filters
     (`--locality`, `--region`, `--postal-code`, `--country-code`) and geometry
     primitives (`--near-lat`, `--near-lng`, `--radius-meters`).
   - Keep “in <place>” as locality filtering and “near <place>” as anchor/radius
     or future named-area resolution; distance remains evidence, not judgment.

5. **Build reusable evidence primitives**
   - Use concrete Guide/Almanac experiments to discover missing source/derived pieces, but keep the stable tool contract small: account scope, freshness/coverage, explicit windows/geography, support counts, uncertainty, source trails, and caveats.
   - Lunch is an acceptance-test example, not the center of the tool.
   - Do not rank a hidden “best” answer inside `swarm-cadence`, and do not make the CLI own the final Robut evidence packet, Guide packet, or explorable interface.

6. **Draft corrections now; apply them only when scoped**
   - Draft human-approved labels, exclusions, aliases, and interpretation
     overrides against real Guide examples, but keep raw evidence untouched.
   - Correction state must be visible, scoped, and human-authored or human-approved before it changes future answers.

## Now

- [x] Add source/account readiness discovery.
  - Implemented `source status [--account <label>]` for account-scope discovery before Robut/LLMs choose an explicit `--account`.
  - It reports config presence, configured accounts, safe v2/historysearch readiness booleans, default raw/SQLite paths, and local evidence availability without network calls, SQLite queries, raw payload reads, or secret output.

- [x] Add official export/takeout import as an audit/completeness backstop.
  - Implemented `db import-files --account <label> --path <dir>`.
  - Export files are indexed in `raw_files` with adapter `export`.
  - Export-only check-ins are normalized into the same SQLite evidence tables.
  - Existing richer v2/API rows are preserved when check-in ids overlap.
  - After full v2 paging, export contributes only 45 retained check-ins that v2 did not return; they are coordinate/timestamp breadcrumbs with no venue or category data.

- [x] Add a first explicit source-overlap/audit command.
  - Implemented `audit overlap` as a read-only raw-source comparison.
  - It compares export vs v2 by check-in id and summarizes timestamp, venue, coordinate, category, and field-coverage differences.
  - Current full account audit: 9,292 overlapping v2/export ids; timestamps match for all overlaps; venue id matches 9,287 and mismatches 5; v2 has categories for 9,284 overlapping rows and export has 0.

- [x] Run first real evidence reads from the now-imported data.
  - Snapshot stored under `.tmp/real-evidence-20260427T055137Z/` (ignored scratch).
  - `db stats`: 18 raw files, 9,359 check-ins, 4,347 venues, 229 categories, oldest 2010-10-17, latest 2026-04-26.
  - Initial partial-v2 snapshot showed historical export rows lacked categories; after full v2 paging, category coverage is now mostly v2-backed.
  - Explicit Japan window `2025-12-23 08..11` returns two real visits; `2025-12-27 05..08` returns zero because the Haneda row is local 15:31, not morning.
  - `query compare` over 2024 baseline vs 2026 recent works, but without geography it surfaces travel/old one-off venues before it can answer locality-shaped Guide questions.

- [x] Add geography constraints before inspecting the first Guide-ready evidence pieces.
  - Added factual Foursquare venue-location filters to `query venues` and `query compare`: `--locality`, `--region`, `--postal-code`, and `--country-code`.
  - Added geometry filters to `query venues` and `query compare`: `--near-lat`, `--near-lng`, and `--radius-meters`.
  - Results include venue location fields and `distance_meters` as evidence.
  - Captured the key semantic distinction: “in San Carlos” means locality; “near San Carlos” should include nearby Redwood City/Belmont venues via an anchor/radius or future `--near-place`/`--area` resolver.

- [x] Build the first experimental diagnostic envelope.
  - Implemented experimental diagnostic output with schema label `swarm_experimental_packet`; naming/API are intentionally provisional and should not imply the CLI owns final packet composition.
  - It composes existing `query venues` and `query compare` results into one experimental JSON diagnostic with explicit account, target window, geography definition, source coverage, sources, and caveats.
  - It includes geography semantics visibly: locality filters are “in place”; anchor/radius filters can include nearby localities.
  - It avoids ranking, recommendation prose, correction state, open-now data, and cross-source joins.

- [x] Add first category/intent-lane filter.
  - Added `query categories` to list known database category names and repeatable exact case-insensitive `--category <name>` filters to `query venues`, `query compare`, and the experimental evidence envelope.
  - This lets “coffee near San Carlos” return coffee-shop evidence across nearby localities instead of generic lunch/restaurant rows.
  - It is still factual Foursquare category evidence, not a fuzzy cuisine/preference model.

- [x] Add an ingest/update loop suitable for cron.
  - Goal shape should resemble `protect-cadence`: safe to run every couple of hours without manual babysitting.
  - Implemented `ingest --account <label> --adapter v2` with defaults `--pages 4`, `--limit 250`, and `--delay-ms 1000`.
  - It preserves raw responses/manifests, imports after each successful page, stops on an existing local check-in id or short page, and reports `updated`, `no_new_checkins`, `updated_partial`, `config_missing`, `source_blocked`, or `import_failed`.
  - Freshness is derived from existing tables: `last_fetched_at`, `last_imported_at`, oldest/latest check-in timestamps, and `current_through` as the latest imported check-in timestamp.
  - `db stats` and the experimental evidence envelope now include freshness fields.
  - This remains v2-only, local-first, read-only with respect to Swarm/Foursquare, and does not add a daemon.

- [x] Add a tool VERSION and include it in provenance.
  - Added repo `VERSION` and Makefile `sync-version` like other local tools.
  - `swarm-cadence --version` prints the synced version, and top-level help shows it.
  - Experimental diagnostic outputs include `tool_version` in JSON and text output.
  - Future build metadata/git SHA can be added later without changing `VERSION` as the stable human/tool contract.

- [x] Add interactive first-run auth login, matching the `protect-cadence` auth shape.
  - Provide a guided auth path for creating the local Application Support config without hand-editing JSON.
  - Check whether a usable Swarm/Foursquare token/config already exists, explain what is missing, and avoid printing secrets.
  - Keep non-interactive/config-file paths for cron and automation.
  - First-run auth should make it obvious where raw files, SQLite, config, and logs/freshness state will live.
  - Added canonical `auth status`, `auth login`, and `auth clear`; `setup` is only a compatibility alias for `auth login`.
  - `auth login` prompts for an account label in auto/text mode when `--account` is omitted, so the first account is labeled and adding a second account is clean.
  - `auth login` supports token paste and Foursquare OAuth code exchange via injectable transport.
  - Config writes merge into `accounts.<label>.v2`, preserve sibling account/historysearch config, and set `0600` permissions where supported.

- [ ] Use [docs/pattern-boundary-and-corrections.md](docs/pattern-boundary-and-corrections.md) to keep `swarm-cadence` as place/visit evidence substrate with simple attached annotations, not the lunch recommender or correction machinery.

- [ ] Create an OpenClaw skill for `swarm-cadence`.
  - Mirror the local-tool pattern used by `protect-cadence`, `clime`, and `paprika-pantry`.
  - Document when to use Swarm evidence, safe read-only/query commands, ingest/update expectations, default paths, and provenance/freshness interpretation.
  - Include guidance for LLM category selection: run `query categories`, choose explicit categories for the task, pass repeated `--category`, and surface selected categories in answers.
  - Keep human-facing answers in Guide/Almanac language; do not expose repo jargon unless debugging.

- [x] Add explicit sorting / multiple evidence views.
  - Current near-radius venue rows sort by distance first, so “top” means nearest, not strongest evidence.
  - Added explicit `--sort nearest|strongest|recent|stale` to `query venues` and `query compare`.
  - JSON filters/results and text output include the effective sort and order label.
  - Defaults remain nearest with geometry filters, strongest for non-geo venue support, and stale for non-geo compare output.
  - Experimental diagnostic envelopes now emit labeled evidence views (`strongest`, `recent`, `stale`, plus `nearest` when geometry filters are present) instead of one ambiguous ranked list.

- [x] Add venue time/cadence rollups as the next small evidence-substrate slice.
  - Implemented `query cadence` for factual venue-level time/cadence rollups over explicit venue/date/hour/geography/category/near-radius filters.
  - Output includes stable venue identity, location/category fields, support counts, first/last seen, days since last visit, distinct local dates, local-hour buckets, ISO weekday buckets, weekday/weekend counts, simple observed gap-day facts, freshness, and `query visits` drill-downs.
  - Kept this descriptive: no “lunch preference,” no best venue, no hidden current-era weighting, and no recommendation prose inside the CLI.

- [x] Add named geography / anchor presets after cadence rollups.
  - Existing `--near-lat`, `--near-lng`, and `--radius-meters` are correct but too manual for repeat Almanac/Guide work.
  - Preserve the existing semantic distinction: “in place” = factual locality/region/postal/country filters; “near place” = anchor/radius evidence that can include neighboring localities.
  - Start with explicit local presets that have proven useful in Almanac work, for example `home`, `jackson-square`, `peninsula`, and maybe `ferry-building` if needed.
  - Implemented command shapes:
    - `query venues --account default --near-place jackson-square --radius-meters 900 --format json`
    - `query venues --account default --area peninsula --category "Coffee Shop" --format json`
  - `query venues`, `query cadence`, `query compare`, and the experimental diagnostic envelope now resolve config-defined `anchor` and `area` presets in the CLI/options layer.
  - Output includes requested/resolved geography definitions, semantics, and effective primitive filters or area-locality selectors.
  - Kept named areas as transparent query expansion / geography evidence, not recommendation logic.

- [x] Add clearer active/lapsed evidence outputs once cadence/geography are stable.
  - Added `query lapses` as a thin evidence-shaped wrapper over the comparison substrate.
  - `query compare` / `query lapses` now include source freshness and observed gap-day facts alongside support counts, first/last seen, comparison windows, categories, geography, and drill-downs.
  - Example command:
    - `query lapses --account default --baseline-from 2018-01-01 --recent-from 2024-01-01 --min-baseline-visits 10 --format json`
  - The tool may say “historically strong, absent recently” or “recently active”; it must not infer “disliked,” “abandoned,” or “favorite” as a final judgment.

- [x] Add a narrow venue identity audit for export/API merge checks.
  - Added `audit identity` over the SQLite evidence store.
  - It reports same-name/same-address and same-name/nearby venue-ID candidates with source-adapter support counts.
  - This is intentionally read-only audit evidence, not aliasing, canonical venue grouping, or automatic merge logic.
  - Example command:
    - `audit identity --account default --format json`

- [ ] Add trip / travel-burst clustering after local source/derived pieces are usable.
  - Motivation: airports, hotels, ski trips, Hong Kong/Taiwan clusters, and other bursts should be separable from ordinary local food/place evidence.
  - The tool can expose bounded travel clusters by country/locality/date gaps; Robut decides how to use them in Almanacs/Guides.
  - Possible command shape:
    - `query trips --account default --country-code TW --gap-days 3 --include localities,categories,top-venues --format json`
  - Keep this descriptive: dates, places, support, top venues/categories, and drill-downs; no travel-personality conclusions.

- [ ] Consider transparent category groups later, only if exact category selection remains too repetitive.
  - Exact `--category` filters and `query categories` remain the source of truth.
  - Saved groups like `coffee-bakery` or `food-broad` could be useful if they are explicit caller/tool-defined sets, rendered in output, and not fuzzy hidden cuisine/preference models.
  - Future output should show which concrete Foursquare categories were included.

- [ ] Draft and exercise correction/edit examples soon, before sidecar storage.
  - Use the attached-note approach in [docs/pattern-boundary-and-corrections.md](docs/pattern-boundary-and-corrections.md): annotations attached to venues, check-ins/windows, categories, geography, or person/family context.
  - Start with human-authored or human-approved Robut/Obsidian notes tied to venue/check-in/category/geography identifiers.
  - Store scoped human corrections / approved overrides separately from raw evidence and derived observations once Guide experiments show which corrections need machine application.
  - Keep any durable form minimal: attached target, note text, source, and updated time.
  - Do not allow LLM-written interpretations to become raw evidence or unmarked human preference; human notes should remain visibly annotations.

- [ ] Support single-account use better.
  - If exactly one account is configured, commands should be able to infer that account when `--account` is omitted.
  - If multiple accounts are configured, `--account` should become required and errors should list the available labels.
  - Preserve explicit `--account` support everywhere; this is a convenience for the common one-person install, not a return to silent account blending.

- [ ] Keep these explicit non-goals while adding the above.
  - Do not add hidden “current-era weighted venue ranking” as a tool-owned score. Expose recent support, historical support, gaps, freshness, and sort modes instead.
  - Do not add “convenience-risk” as tool truth. Expose features that let Robut say “this might be convenience” and ask for correction.
  - Do not make `swarm-cadence` own open-now/current availability as core Swarm truth. Treat live/open data as a separate current-source join above or beside Swarm unless Foursquare metadata clearly supports a bounded factual field.
  - Do not make the CLI own final Almanacs, Guides, evidence packets, or explorable interfaces. `swarm-cadence` provides stable source/derived pieces; Robut/LLM composes scenario meaning and human-facing artifacts.

## Recently completed

- [x] Migrated ignored repo-local account evidence into the new Application Support layout.
  - Source: `data/raw/v2/checkins` and `data/swarm-cadence.sqlite`.
  - Destination: `~/Library/Application Support/swarm-cadence/accounts/<account>/`.
  - Result: 4 imported v2 pages / 1,000 check-ins / 642 venues / 175 categories in the default account DB.
  - Also migrated `.swarm-cadence.env` into local `config.json` without committing secrets.
- [x] Build the raw-file manifest index in SQLite.
  - `raw_files` tracks source path/name, SHA, bytes, fetched_at, adapter,
    account, endpoint, API version, limit, offset, status, returned count,
    total count, and import time.
- [x] Fetch/import one or a few recent v2 API pages.
  - Existing ignored repo-local data includes offsets `0`, `250`, `500`, and
    `750` at `limit=250`, all HTTP/API 200, now migrated to defaults.
- [x] Add first two-account fixture/default coverage.
  - Multiple people are first-class account profiles under Application Support.
  - Per-account raw and SQLite defaults are separate; no silent blending.
- [x] Add first evidence queries over imported v2 SQLite.
  - `query venues` and `query visits` expose visit counts, first/last seen,
    categories, account scope, and drill-down descriptors.
- [x] Define query/almanac timezone semantics.
  - Normal date/hour query filters use experienced local check-in time from
    ingest-time sidecar fields.
  - UTC/absolute-time variants should be explicit if added later.
- [x] Add calendar/time-of-day query filters.
  - `--date`, `--hour-from`, and `--hour-to` use `local_date` / `local_hour`.
  - Fuzzy labels like lunch/morning stay above the low-level CLI.
- [x] Add a generic explicit-window experimental evidence envelope.
  - `evidence window` emits `swarm_window_evidence_packet.v0` over explicit
    date/hour filters.
- [x] Add generic venue cadence comparison facts.
  - `query compare` compares baseline vs recent support by venue, with optional
    hour filters, min baseline support, last seen, age, categories, and
    drill-down.

## Later / after real-data inspection

- [x] Add deliberate multi-page API fetch for explicit enrichment/backfill.
  - Implemented `raw fetch-pages` with `--pages` capped at 200, `--limit` capped at 250, and `--delay-ms` defaulting to 1000.
  - The command writes raw files/manifests only; import remains a separate `db import-raw` step.
  - It stops early on non-success status or a short page.
  - Ran account backfill from offset 2000 with 30 requested pages; fetched 30 pages / 7,315 raw items, stopping at offset 9250 with a short 65-item page. Last observed rate-limit remaining: 466/500.
  - Imported raw v2 backfill: default account DB now has 48 raw files, 9,359 check-ins, 4,348 venues, and 389 categories; retained rows are 9,314 v2 + 45 export-only.
  - Full post-fetch audit: 9,292 overlapping v2/export ids; timestamps match for all overlaps; venue id matches 9,287 and mismatches 5; v2 has categories for 9,284 overlapping rows and export has 0.
- [ ] Keep `historysearch` as a narrow fallback if v2 becomes blocked for an
  account.
- [ ] Add venue reconciliation: closed/renamed status, aliases, categories, and
  lat/lng confidence.
- [ ] Add derived observations: active/lapsed support facts, meal-window
  support, gaps, and geography clusters; leave favorite/preference labels above the CLI.
- [ ] Add correction/edit storage after drafted examples show which scoped corrections need machine application.
- [ ] Add Paprika and `clime` join inputs only above the CLI, with explicit join boundaries; avoid making `swarm-cadence` orchestrate sibling-tool packets.
- [ ] Document the SQLite exploration surface with read-only inspection queries for
  coverage, date ranges, venues, and category completeness.

## Not now

- No generic Foursquare SDK.
- No write/sync-back to Swarm/Foursquare.
- No hidden background sync.
- No opaque recommender or hidden score.
- No silent account blending.
- No cross-source joins without a visible purpose and boundary.
