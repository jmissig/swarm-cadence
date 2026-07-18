# AGENTS.md — swarm-cadence

This file gives coding agents the durable context they need to work safely and consistently in this repository.

Preserve `swarm-cadence`’s purpose. Do not broaden it into a generic location platform, recommender engine, or Foursquare SDK unless Julian explicitly asks.

## Project posture

Current posture: **early exploration**

`swarm-cadence` is a small local-first CLI for ingesting, storing, querying, and eventually modeling Foursquare Swarm check-in history for OpenClaw/Robut.

Project posture controls how aggressive architecture, schema, dependency, and cleanup changes should be.

- **Early exploration** — sweeping architecture, schema, dependency, and command-surface changes are welcome when they fit the emerging shape. Debate requirements, then commit to the new direction and remove old paths cleanly.
- Prefer current recommended patterns and tools over preserving old approaches.
- Backwards compatibility is not a default goal until real user data, scripts, or operator workflows depend on a shape.

Underlying philosophy: **software is ephemeral**. Old code should earn its keep. Keep the project alive by letting it change deliberately.

## Project brief

`swarm-cadence` is a small local-first evidence tool for Foursquare Swarm check-ins.

This project is:

- a command-line tool for logging, ingesting, and querying Swarm check-in history;
- a local SQLite evidence store for personal/location traces owned by Julian/Alice, not a cloud product;
- a future OpenClaw/Robut grounding tool for questions like “where should I grab lunch today?”;
- a place to preserve raw Swarm/Foursquare data, normalize venues/check-ins, and compute boring descriptive facts;
- a sibling in spirit to `clime`, `protect-cadence`, and `paprika-pantry`.

Source of truth:

- Canonical external source: Foursquare/Swarm check-in history for each configured account.
- Canonical local evidence: the local `swarm-cadence` SQLite database once records are ingested.
- Raw source payloads: preserved in the evidence DB or adjacent raw archive so future schemas can be re-derived.
- Derived/cached data: model/derived tables or sidecar DBs for cadence, venue rollups, source/derived outputs, and human-annotations; these should be rebuildable from local evidence plus annotation storage. Evidence packets are Robut/LLM-composed artifacts above the stable CLI pieces, except for explicitly experimental diagnostic envelopes.
- Research/design sources:
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/Coding/Foursquare Swarm Connector.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/Coding/Pattern Extraction Tooling.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Intelligence Research Index.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Almanacs and Guides.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/Family/Julian’s Food & Places Almanac v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide Source Bundle v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/Coding/Canonical AGENTS.md`
- Human-facing usage guide: `README.md`.
- Active backlog: `TODO.md`.
- Focused design/API/schema docs: `docs/`, especially `docs/pattern-intelligence-proposal.md`.

Never write to:

- Swarm/Foursquare check-ins, venues, profile data, or remote account state;
- another person’s account data without explicit configuration and consent;
- ambient/default operator databases, configs, or token stores during routine verification;
- installed binaries or installed OpenClaw skills during routine tests;
- production/default local evidence stores during tests unless Julian explicitly asks for a live smoke test.

Non-goals / anti-goals:

- not a Foursquare/Swarm replacement app;
- not a social network client;
- not a generic Places API SDK;
- not a write/sync-back tool — “sync” means pull/ingest into local storage only;
- not a browser automation project unless credential realities force a narrow fallback;
- not an opaque recommendation engine;
- not a dashboard-first product;
- not a place to freeze Julian or Alice into stale preference labels;
- not a tool that joins location data with unrelated household sources by default.

Attractive but wrong expansion: **do not build a general personal-location intelligence empire.** Build the small connector/evidence layer that makes local Swarm history inspectable and useful.

## Current state

The repository is now a Swift Package Manager project with:

- executable target `swarm-cadence`;
- library target `SwarmCadenceCore`;
- `swift-argument-parser` for CLI option parsing behind the testable `SwarmCadenceCommand.run(...)` seam;
- GRDB-backed SQLite import/stats code;
- explicit dry `source probe` for `v2` and `historysearch` config validation;
- explicit live v2 source probe for one read-only `GET /v2/users/self/checkins` request with `limit=1`;
- Application Support defaults: `config.json`, plus per-account `raw/v2/checkins` and `swarm-cadence.sqlite` under `~/Library/Application Support/swarm-cadence/accounts/<account>`;
- JSON config with first-class `accounts.julian` and `accounts.alice` sections;
- conservative `raw fetch --adapter v2` that performs exactly one read-only v2 check-ins request and writes one raw file plus one redacted manifest;
- cron-friendly `ingest --adapter v2` that fetches bounded recent pages, preserves each raw file/manifest, imports after each successful page, and reports factual freshness/status for unattended logs;
- `Makefile` wrappers for build/test/release/default inspection/config bootstrap;
- offline `db import-raw` from preserved v2 raw/manifest pairs;
- aggregate-only `db stats` with derived freshness fields (`last_fetched_at`, `last_imported_at`, and `current_through` as the latest imported check-in timestamp);
- account-scoped `query venues` and `query visits` over the imported SQLite sidecar, including factual local-calendar filters (`--date`, `--hour-from`, `--hour-to`);
- venue geography filters from factual Foursquare location fields (`locality`, `region`, `postal_code`, `country_code`) and explicit map-distance primitives (`--near-lat`, `--near-lng`, `--radius-meters`), with distance returned as evidence;
- `query categories` for inspecting known category names, plus repeatable factual category filters `--category <name>` for caller-chosen intent lanes, threaded through venue, cadence, compare, and experimental evidence-envelope queries;
- import-time local-time sidecar fields for visits when raw timezone evidence is available (`local_date`, `local_hour`, `local_weekday_iso`, timezone id/offset), while retaining UTC `createdAt` as canonical provenance;
- factual venue time/cadence rollups (`query cadence`) over explicit venue/date/hour/geography/category filters, returning support counts, first/last seen, gaps, local-hour buckets, ISO weekday buckets, weekday/weekend counts, freshness, and visit drill-downs without recommendation labels;
- generic venue cadence comparisons over explicit baseline/recent windows (`query compare`) for active/lapsed/rotation evidence;
- generic builder-facing `evidence window` packets over explicit date/hour filters, without fuzzy meal/time labels in the CLI;
- first experimental diagnostic envelope, which composes venue support and cadence comparison facts with explicit target window, geography semantics, source coverage, sources, and caveats; its name/schema are provisional and not a durable API commitment and should not imply the CLI owns final packet composition;
- fixture/temp-path tests for probes, raw fetch behavior, parser validation, redaction, import idempotency, aggregate stats, two-account defaults, first evidence queries, and local-time sidecar output.

The v2 API direction is proven locally for Julian and should be exercised for Alice as a first-class second account. Treat v2 OAuth as the primary source path unless it becomes blocked for an account or token/app setup. Keep `historysearch` as a narrow fallback, and keep official export/takeout import as an audit/completeness backstop for rows the API does not return.

Current command surface:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json
swarm-cadence source probe --account alice --adapter v2 --format json
swarm-cadence raw fetch --account julian --adapter v2 --limit 250 --offset 0
swarm-cadence raw fetch --account alice --adapter v2 --limit 250 --offset 0
swarm-cadence ingest --account julian --adapter v2 --format json
swarm-cadence ingest --account alice --adapter v2 --format json
swarm-cadence db import-raw --account julian --format json
swarm-cadence db import-raw --account alice --format json
swarm-cadence db stats --account julian --format json
swarm-cadence db stats --account alice --format json
swarm-cadence query venues --account julian --format json
swarm-cadence query visits --account julian --venue-id <venue-id> --format json
swarm-cadence query cadence --account julian --venue-id <venue-id> --from 2024-01-01 --format json
```

Near-term critical path:

1. Fetch v2 API pages at `limit=250` to prove the live source, current schema, and category/venue richness.
2. Build/finish the SQLite raw-file manifest index and import those API raw files.
3. Add official export/takeout import as an audit/completeness backstop.
4. Compare overlapping API vs export data by check-in id before trusting source semantics.
5. Preserve export-only coordinate/timestamp breadcrumbs, but prefer API rows where both exist.
6. Import and inspect real coverage with `db stats`, `query venues`, `query visits`, `query cadence`, and `query compare`.
7. Use geography constraints in real Guide/Almanac reads, keeping “in <place>” and “near <place>” semantics distinct.
8. Inspect first experimental diagnostic envelopes and decide the next reusable evidence gap: named-place/area resolution, active/lapsed support facts, venue reconciliation, or human-readable Guide rendering above the CLI.
9. Add correction/derived model state only after source/derived outputs show what actually needs correcting.

Keep raw files as source of truth and the SQLite DB rebuildable. Build generic cadence/evidence query tools before any recommendation-like or guide-specific surface. Preserve account separation throughout.

Do not broaden this into a general connector while filling in the next slices.

## Validation

Routine checks:

```bash
make build
make test
```

In sandboxed environments that block SwiftPM's default cache paths, use
repo-local caches:

```bash
mkdir -p .tmp/home .build/clang-module-cache
HOME=$PWD/.tmp/home CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache swift test --disable-sandbox
```

Direct SwiftPM equivalents remain fine when needed:

```bash
swift build
swift test
```

Do not run during routine verification:

- install/publish commands;
- commands that mutate real Swarm/Foursquare state;
- commands that write to default real token/config/database/raw paths;
- live credential probes unless Julian explicitly asks and credentials/config are already provided safely;
- destructive cleanup of evidence/model databases outside repo-local/temp/fixture paths.

Use repo-local, fixture, sandboxed, or temporary paths for tests and smoke checks. Prefer explicit `--db`, `--config`, `--account`, `--raw-dir`, and `--out` paths when exercising commands.

## Core principles

- Keep `swarm-cadence` narrow and purpose-built.
- Preserve raw evidence before deriving patterns.
- SQLite/local-first storage is the durable substrate.
- Separate source adapters, normalization, storage, derived facts, and CLI presentation.
- Keep external API or browser-session details behind thin, replaceable ingest boundaries.
- Treat credential/token handling as a sensitive boundary.
- Treat separate Julian/Alice sourcing as a core architecture constraint, not an afterthought.
- Keep account identity explicit; do not silently blend Julian and Alice.
- The CLI exposes evidence. OpenClaw/Robut handles judgment, phrasing, and conversation.
- Treat check-ins as evidence of visits, not proof of preference.
- Derived labels are provisional handles, not permanent facts about a person.
- Prefer boring, inspectable facts: counts, first/last visits, gaps, windows, support, freshness, provenance, drill-downs.
- Prefer source/derived rows, explicit filters, alternatives, and visible exclusions over one hidden “best” answer.
- Preserve uncertainty and source quality; mark inferred categories and stale metadata.
- Avoid over-joining personal data. Each cross-source join needs a purpose and a privacy/agency reason.
- Do not let location history become surveillance exhaust. Build for reflection and situated help, not creepiness.

## Architecture guidance

Preferred high-level flow:

```text
Swarm/Foursquare source
    -> ingest adapter: v2 OAuth OR Swarm web historysearch OR export import
    -> raw payload preservation
    -> normalized SQLite evidence store
    -> derived descriptive model layer / optional sidecar
    -> query verbs + builder-facing source/derived outputs
    -> Robut-composed packet / Food & Places Almanac / Lunch Guide
    -> OpenClaw / Robut conversation + edit/correction loop
```

Rules:

- Build a stable local evidence layer with replaceable ingest adapters.
- Do not tie the schema to one fragile source path.
- Preserve raw JSON/source payloads so parser/schema mistakes can be corrected later.
- Normalize into stable local entities: accounts, check-ins, venues, categories, photos when available, sync state, and provenance.
- Do not mirror every Foursquare/Swarm field unless it supports evidence, replay, debugging, or future derivation.
- Keep SQL and schema changes explicit and inspectable.
- Store timestamps as unambiguous instants; render/group in local time at query boundaries.
- Keep `raw evidence DB` and `derived/model DB` separable if the model layer becomes non-trivial.
- Do not store LLM-generated interpretations in base evidence tables.
- After a directional change, make the new path the real path. Delete or clearly retire superseded code, docs, files, TODOs, and stale architectural discussion unless they are needed for migration or recovery.

## Geography semantics

Do not flatten human place language into a single city-name filter.

Durable distinction:

- **“in San Carlos”** means a factual venue-location filter, e.g. Foursquare
  venue `locality = San Carlos` plus optional `region`/`country_code`.
- **“near San Carlos”** means San Carlos is an anchor/area, then nearby venues
  may include Belmont, Redwood City, etc. Use geometry/bounds around the anchor
  and return each venue's factual locality plus `distance_meters` as evidence.
- **“San Carlos / Redwood City area”** means an explicit area definition, such as
  a named city set, polygon, or bounding shape. Do not silently turn it into one
  city unless the caller asked for “in”.

This was learned from the concrete case: coffee near San Carlos should include
Redwood City coffee places when they are only a few kilometers away. Strict
`--locality "San Carlos"` is correct for “in San Carlos” but wrong for “near San
Carlos”.

Interim CLI guidance:

- `--locality`, `--region`, `--postal-code`, and `--country-code` are factual
  Foursquare venue-location filters.
- `--near-lat`, `--near-lng`, and `--radius-meters` are geometry primitives.
  They must be used together and should return `distance_meters` rather than
  hiding the judgment.
- Combining locality and radius is an AND refinement, not the default semantics
  of “near <place>”. Use it only when that is actually intended.
- Prefer future `--near-place` / `--area` work to resolve human phrases into an
  inspectable anchor, city-set, bounds, or polygon before applying geometry.
- Keep low-level CLI filters factual; fuzzy names and user-facing phrasing belong
  in the Almanac/Robut layer, backed by explicit filter definitions.

## Ingest strategy

The research recommendation is adapter-first, not source-path absolutism. The
v2 OAuth path has been proven locally for Julian, so use it as the primary path
for the next evidence/query slices while keeping the fallback boundaries clear:

1. **v2 OAuth user check-ins** — primary path for Julian, and the expected first path to probe for Alice.
2. **Credential probe per account** — Alice is a first-class simultaneous account, not a later optional add-on; test whether each configured account can call `GET /v2/users/self/checkins`.
3. **Official export/takeout** — audit/completeness backstop after API proof/backfill exists; useful for API-missing coordinate/timestamp breadcrumbs.
4. **Swarm web `historysearch`** — narrow fallback if v2/export fail because of gating, `402`, app restrictions, missing export coverage, or unusable token flow.
5. **Current Places APIs** — venue enrichment only, not check-in history.

Important: v2 is proven enough to build the next local evidence/query slices,
not a broad connector or Foursquare SDK.

### Credential and account handling

- Keep credentials outside git in `~/Library/Application Support/swarm-cadence/config.json` by default; do not use repo dotfiles as the normal config home.
- Keep credentials, raw payloads, generated data, and SQLite evidence files out of git; checked-in fixtures must be synthetic.
- Avoid printing tokens, cookies, OAuth params, or browser-session details in logs, test failures, or examples.
- Account profiles should be explicit, e.g. `julian`, `alice`, or another configured label.
- Each account has its own source credentials, sync state, provenance, raw payloads, raw archive, and SQLite evidence database under the same local Application Support app root unless explicitly overridden.
- Do not design around a single global Swarm identity and add multi-account later. This repo is the first local pattern tool where separate Julian/Alice sourcing is a first-order requirement.
- Multi-account queries must preserve account attribution.
- Joint/family outputs are allowed only when the command/query is explicitly scoped that way.
- Treat browser-session approaches as sensitive and brittle. Keep them isolated behind an adapter and documented as fallback.

## Default local paths

Normal operator defaults mirror the other installed CLI tools and live under Application Support rather than repo-local dotfiles:

```text
~/Library/Application Support/swarm-cadence/config.json
~/Library/Application Support/swarm-cadence/accounts/julian/raw/v2/checkins
~/Library/Application Support/swarm-cadence/accounts/julian/swarm-cadence.sqlite
~/Library/Application Support/swarm-cadence/accounts/alice/raw/v2/checkins
~/Library/Application Support/swarm-cadence/accounts/alice/swarm-cadence.sqlite
```

`config.json` is account-structured: `accounts.julian` and `accounts.alice` are first-class sibling account profiles. Default raw and SQLite paths are also per-account. Environment variables and explicit `--config`, `--db`, `--raw-dir`, and `--out` paths remain available for tests, probes, and sandboxed runs.

## Data model sketch

Do not overfit this before the probe, but expected core tables are:

- `accounts(id, label, display_name, source_kind, created_at, last_sync_at, last_success_at)`, where `label` is the stable local handle such as `julian` or `alice`
- `checkins(id primary key, account_id, created_at, tz_offset, venue_id, venue_name, lat, lng, city, state, country, shout, type, raw_json, source, fetched_at)`
- `venues(id primary key, name, lat, lng, address, city, state, country, categories_json, raw_json, updated_at)`
- `photos(id primary key, checkin_id, account_id, url, raw_json)`
- `sync_state(account_id, source, newest_created_at, newest_checkin_id, oldest_created_at, cursor_json, last_status, last_error)`

Likely derived/model concepts later:

- visit counts by venue/category/time window;
- first/last visit;
- median/typical gap;
- days since last visit computed at query time;
- recent share vs historical share;
- meal-window affinity;
- home/work/travel or geography clusters where explicitly supported;
- active/lapsed support facts, gap facts, and context windows;
- human-approved corrections and scoped exclusions.

## CLI / local tool guidance

This tool should feel like Julian’s other local-first CLIs:

- small local-first CLI;
- explicit source/config/database boundaries;
- compact output by default for human operators;
- structured output via `--format json` for agents/scripts;
- narrow evidence-oriented commands;
- clear `doctor`, `status`, or `validate` commands when useful;
- interactive setup/auth/config flows only where they help humans, with complete one-shot forms for agents and scripts;
- no hidden background behavior in v1.

Likely early command surface:

```bash
swarm-cadence source probe --account julian --format json
swarm-cadence ingest recent --account julian --since 7d --format json
swarm-cadence ingest backfill --account julian --format json
swarm-cadence import export --account julian ./foursquare-export/checkins.json --format json
swarm-cadence query recent --account julian --limit 20 --format json
swarm-cadence query visits --account julian --venue "Cafe" --since 1y --format json
swarm-cadence query stats --account julian --by category --since 90d --format json
swarm-cadence doctor --format json
```

Possible later commands:

```bash
swarm-cadence model rebuild
swarm-cadence model patterns --account julian --since 1y --format json
swarm-cadence evidence lunch --account julian --near home --format json
```

Command names are provisional, but prefer `source probe` because the command should cover adapter viability, field coverage, and credential health without implying an auth-only task. Prefer the smallest coherent command set that answers real questions.

Align shared verbs where they mean the same thing across tools, and use Swarm-specific verbs only when they name a real source or evidence shape.

Interactive vs one-shot:
- human setup/auth/config flows may be guided, but `source`, `ingest`, `import`, `query`, and `doctor` forms should stay scriptable
- JSON, non-TTY, and `--non-interactive` / `--no-input` modes must never prompt
- destructive repairs or identity/account changes need explicit scope plus preview or confirmation; bounded source fetches, ingests, and imports remain one-shot and non-interactive

### Output

- Default output should be concise and useful to a human operator.
- Use `--format json` for machine-readable output.
- `--json` may exist as shorthand, but docs and examples should prefer `--format json`.
- JSON should include effective filters/bounds, source freshness, account scope, counts/denominators, and provenance where relevant.
- Avoid narrating conclusions. Return evidence and let the caller interpret it.
- For any experimental evidence envelope or source/derived output, include drill-down descriptors that reproduce the supporting query.

## Pattern intelligence guidance

`swarm-cadence` is the most direct testbed for the pattern-intelligence research because the acceptance test is concrete:

> Julian asks: “Where should I grab lunch today?”

The tool should not answer “best lunch” by itself. It should provide source/derived outputs that let Robut compose any evidence packet, Almanac, or Guide above the CLI.

### Research and redesign posture

This repo is especially vulnerable to overfitting because it sits near several successful sibling tools and an attractive Almanac/Guide layer. Use the `deep-researcher` anti-anchoring rule for design-heavy work:

> Improvements to local tools can be output, but only vibes should be input.

Start with the human problem, desired outcome, privacy boundary, and acceptance feel. Treat existing tools, current envelopes, and sibling CLIs as constraints, taste signals, and later acceptance tests, not as the search space.

Default sequence for research-shaped changes:
- frame the question and the decision or workflow it should support
- survey outward: prior art, current APIs, local-first evidence tools, geography semantics, search/indexing patterns, and comparable guide/almanac products
- map options before choosing a command, schema, packet, or correction model
- unblind the local implementation and adapt the broader map to `swarm-cadence`’s early-exploration posture
- turn the result into a small implementation slice, focused TODO/doc update, or explicit decision

Keep survey, decision, and implementation plan distinct. A sibling command shape is useful evidence of house style, not a substitute for deciding what this tool itself needs.

Useful pattern-extraction verbs for this project:

- prepare/scope the query;
- collect/import/preserve raw traces;
- normalize venues/check-ins/categories/geography;
- integrate/join cautiously;
- summarize/roll up;
- compare against baselines;
- detect change/deviation without dramatizing it;
- segment by context, geography, time window, and era;
- classify provisionally;
- find recurrence/cadence/lapse/resumption;
- find co-occurrence/association;
- surface source/derived rows, alternatives, mechanical exclusions, and uncertainty;
- explain/cite/drill down;
- simulate or adjust assumptions;
- critique/correct/update edits and interpretation records;
- decay/retire stale patterns;
- export/transfer/preserve.

Useful source facts for lunch Guide inputs:

- nearby active anchors;
- active/lapsed support facts;
- lunch-window support vs dinner-only support;
- recent vs historical frequency;
- category/cuisine lanes;
- travel radius / geography cluster;
- stale import warnings;
- open-now/enrichment status when available;
- mechanical exclusions and filter limits;
- uncertainty and inferred labels.

### Two-surface design

Build toward two sibling surfaces over the local evidence:

1. **SQLite/Datasette-style explore/inspect surface**
   - read-only browsing, faceting, ad hoc SQL, source coverage, schema inspection, and debugging;
   - useful for humans and trusted agents discovering questions;
   - not the normal conversational contract.

2. **Stable verb / evidence-substrate surface**
   - bounded CLI commands and JSON/source outputs for Robut;
   - safe defaults, explicit semantics, provenance, drill-downs, and privacy/join policy;
   - normal chat should use this instead of improvised arbitrary SQL;
   - Robut or a dedicated artifact layer owns the final packet, Guide, or explorable interface.

## Privacy, agency, and correction boundaries

- Location history is sensitive. Treat it as private evidence, not ambient context to be sprayed everywhere.
- Do not join Swarm data with cameras, calendar, Paprika, clime, messages, or other household data unless a query explicitly needs it or a documented policy allows it.
- If Robut includes a source in a cross-source packet above the CLI, the packet should explain why it was included and what it contributed.
- Support corrections without rewriting raw check-ins:
  - “that was convenience, not preference”;
  - “don’t suggest this for lunch”;
  - “still like it, just forgot”;
  - “this is Alice’s preference, not Julian’s”;
  - “closed / renamed / bad metadata”;
  - “only relevant with kids/guests/work travel.”
- Corrections should be scoped, timestamped, and provenance-carrying.
- Old labels must decay or carry active windows. A 2018 favorite should not masquerade as a 2026 current preference.

## Tool and dependency posture

Preferred stack unless a strong reason appears otherwise:

- Swift;
- Swift Package Manager;
- `swift-argument-parser`;
- SQLite;
- GRDB, used lightly;
- `Makefile` wrappers for common commands once useful.

Use GRDB for:

- opening SQLite databases;
- migrations;
- parameterized queries;
- straightforward row decoding;
- transaction boundaries;
- fixture/temp DB tests.

Avoid:

- elaborate ORM patterns;
- deep protocol layering without a concrete seam;
- abstraction that hides SQL shape;
- broad Foursquare SDK surfaces;
- framework-heavy designs;
- clever async/background architecture before there is a concrete need;
- dependency sprawl that obscures simple data flow.

For major architecture choices — persistence, auth, ingest adapters, query grammar, output formats, modeling, testing — do a quick current tool/library scan before inventing custom infrastructure.

## Testing and verification

Prefer tests for:

- OAuth/API response parsing using sanitized fixtures;
- historysearch response parsing using sanitized fixtures;
- export/takeout import parsing;
- idempotent ingest/upsert behavior;
- migration behavior;
- sync high-water/cursor behavior;
- account separation, independent sync state, and joint-query labeling;
- timestamp/local-time grouping;
- query filters and count semantics;
- source/derived-output shape stability;
- token redaction in logs/errors.

Routine tests must not require live credentials or network.

Live credential probes are manual/special checks and should:

- require explicit config;
- redact sensitive values;
- use minimal limits;
- save only sanitized fixtures when needed;
- never be part of ordinary CI/routine validation.

## Documentation and project hygiene

Use this docs split by default:

- `README.md` — human-facing usage guide: purpose, setup, normal commands, examples.
- `TODO.md` — active backlog / near-term parking lot, if needed.
- `AGENTS.md` — durable architecture, constraints, source-of-truth boundaries, project posture, validation commands, and agent guidance.
- `docs/` — focused contracts/specs that would bloat `AGENTS.md`, such as credential probe annotations, schema docs, source/derived-output schemas, Datasette/exploration recipes, source API contracts, and migration decisions.

Completed work should leave `TODO.md` and live in git history, tests, code, and release notes if relevant.

When architecture choices change, update a decision section or relevant project docs with:

- date;
- decision;
- alternatives considered;
- rationale;
- migration impact.

If unresolved, mark it as `OPEN` with the next checkpoint.

## GitHub / external actions

Read-only GitHub operations are fine when needed.

Before GitHub-facing writes such as PR creation, issue comments, or PR comments:

- check project contribution rules;
- ensure Julian has reviewed and owns the change;
- do not add AI-generated footers or co-author lines unless the project explicitly requires them;
- prefer showing the diff/PR text for human review rather than submitting autonomously.

## Failure signals

Watch for:

- the CLI starts ranking or moralizing without showing evidence;
- source adapters leak raw API/browser details into query/model/presentation layers;
- tokens, cookies, OAuth params, or account identifiers appear in logs, fixtures, or committed files;
- Julian and Alice data become silently blended;
- `swarm-cadence` turns into a generic Foursquare/Places SDK;
- arbitrary SQL becomes the default way Robut answers normal chat questions;
- derived labels lack support counts, generated-at timestamps, or active windows;
- old patterns are treated as current preferences;
- cross-source joins happen without explicit purpose or privacy boundary;
- a dashboard/prototype replaces the evidence API instead of sitting beside it.

## Working style for agents

- Start by reading `AGENTS.md`, `README.md`, `TODO.md` if present, and focused docs relevant to the task.
- For research-shaped work, check the Obsidian source annotations listed above.
- Make the smallest coherent change that solves the real problem.
- Challenge scope drift kindly and directly.
- Keep code, schemas, command surfaces, and docs easy to inspect after time away.
- Prefer trade-off analysis over generic best-practice language.
- When uncertain, choose the narrower interpretation and ask before broadening scope.

## Final rule

Build the small thing that does its job clearly.

Do not build an empire.
