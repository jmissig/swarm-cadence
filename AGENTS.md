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
- Derived/cached data: model/derived tables or sidecar DBs for cadence, venue rollups, candidate sets, labels, and evidence packets; these should be rebuildable from local evidence plus human corrections.
- Research/design sources:
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Foursquare Swarm Connector.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Extraction Tooling.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Intelligence Research Index.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Almanacs and Guides.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Julian’s Food & Places Almanac v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide Source Bundle v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide v0.md`
  - `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Canonical AGENTS.md`
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
- conservative `raw fetch --adapter v2` that performs exactly one read-only v2 check-ins request and writes one raw file plus one redacted manifest;
- offline `db import-raw` from preserved v2 raw/manifest pairs;
- aggregate-only `db stats`;
- fixture/temp-path tests for probes, raw fetch behavior, parser validation, redaction, import idempotency, and aggregate stats.

The v2 API direction is proven locally for Julian. Treat v2 OAuth as the primary source path unless it becomes blocked for another account or future token/app setup. Keep `historysearch` as a narrow fallback, and keep official export/takeout import as a later bootstrap/backfill/reconciliation path.

Current command surface:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json --config ./.swarm-cadence.env
swarm-cadence source probe --account julian --adapter v2 --format json --config ./.swarm-cadence.env --live
swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250 --offset 0
swarm-cadence db import-raw --db data/swarm-cadence.sqlite --raw-dir data/raw/v2/checkins --format json
swarm-cadence db stats --db data/swarm-cadence.sqlite --format json
```

Near-term direction:

- add evidence queries over the imported SQLite sidecar;
- keep the raw v2 files as source of truth and the SQLite DB rebuildable;
- add lunch-window/venue-support facts before any recommendation-like surface;
- preserve account separation from the first query slice;
- add `Makefile` wrappers when they clarify common build/test commands.

Do not broaden this into a general connector while filling in the next slices.

## Validation

Routine checks:

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

If a Makefile is added, prefer the wrapper commands:

```bash
make build
make test
```

Do not run during routine verification:

- install/publish commands;
- commands that mutate real Swarm/Foursquare state;
- commands that write to default real token/config/database paths;
- live credential probes unless Julian explicitly asks and credentials/config are already provided safely;
- destructive cleanup of evidence/model databases outside repo-local/temp/fixture paths.

Use repo-local, fixture, sandboxed, or temporary paths for tests and smoke checks. Prefer explicit `--db`, `--config`, `--account`, and source-file paths when exercising commands.

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
- Derived labels are provisional handles, not permanent facts about a person.
- Prefer boring, inspectable facts: counts, first/last visits, gaps, windows, support, freshness, provenance, drill-downs.
- Prefer candidate sets, alternatives, exclusions, and evidence packets over one hidden “best” answer.
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
    -> query verbs + builder-facing source bundles / evidence packets
    -> Food & Places Almanac / Lunch Guide
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

## Ingest strategy

The research recommendation is adapter-first, not source-path absolutism. The
v2 OAuth path has been proven locally for Julian, so use it as the primary path
for the next evidence/query slices while keeping the fallback boundaries clear:

1. **v2 OAuth user check-ins** — primary path for Julian after the successful credential probe.
2. **Credential probe per account** — still test whether each configured account can call `GET /v2/users/self/checkins`.
3. **Swarm web `historysearch`** — narrow fallback if v2 fails because of gating, `402`, app restrictions, or unusable token flow.
4. **Official export/takeout** — bootstrap, backfill, and reconciliation.
5. **Current Places APIs** — venue enrichment only, not check-in history.

Important: v2 is proven enough to build the next local evidence/query slices,
not a broad connector or Foursquare SDK.

### Credential and account handling

- Keep credentials outside git.
- Avoid printing tokens, cookies, OAuth params, or browser-session details in logs, test failures, or examples.
- Account profiles should be explicit, e.g. `julian`, `alice`, or another configured label.
- Each account has its own source credentials, sync state, provenance, raw payloads, and evidence rows.
- Do not design around a single global Swarm identity and add multi-account later. This repo is the first local pattern tool where separate Julian/Alice sourcing is a first-order requirement.
- Multi-account queries must preserve account attribution.
- Joint/family outputs are allowed only when the command/query is explicitly scoped that way.
- Treat browser-session approaches as sensitive and brittle. Keep them isolated behind an adapter and documented as fallback.

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
- lapsed favorites / active anchors / convenience repeats as provisional labels;
- human corrections and scoped exclusions.

## CLI / local tool guidance

This tool should feel like Julian’s other local-first CLIs:

- small local-first CLI;
- explicit source/config/database boundaries;
- compact output by default for human operators;
- structured output via `--format json` for agents/scripts;
- narrow evidence-oriented commands;
- clear `doctor`, `status`, or `validate` commands when useful;
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

### Output

- Default output should be concise and useful to a human operator.
- Use `--format json` for machine-readable output.
- `--json` may exist as shorthand, but docs and examples should prefer `--format json`.
- JSON should include effective filters/bounds, source freshness, account scope, counts/denominators, and provenance where relevant.
- Avoid narrating conclusions. Return evidence and let the caller interpret it.
- For evidence packets, include drill-down descriptors that reproduce the supporting query.

## Pattern intelligence guidance

`swarm-cadence` is the most direct testbed for the pattern-intelligence research because the acceptance test is concrete:

> Julian asks: “Where should I grab lunch today?”

The tool should not answer “best lunch” by itself. It should provide builder-facing source bundles / evidence packets that let Robut power human-facing Almanacs and Guides.

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
- surface candidates, alternatives, and exclusions;
- explain/cite/drill down;
- simulate or adjust assumptions;
- critique/correct/update edits and interpretation records;
- decay/retire stale patterns;
- export/transfer/preserve.

Strong candidate facts for lunch evidence packets:

- nearby active anchors;
- lapsed favorites;
- lunch-window support vs dinner-only support;
- recent vs historical frequency;
- category/cuisine lanes;
- travel radius / geography cluster;
- stale import warnings;
- open-now/enrichment status when available;
- exclusions and why candidates were not included;
- uncertainty and inferred labels.

### Two-surface design

Build toward two sibling surfaces over the same local evidence:

1. **SQLite/Datasette-style explore/audit surface**
   - read-only browsing, faceting, ad hoc SQL, source coverage, schema inspection, and debugging;
   - useful for humans and trusted agents discovering questions;
   - not the normal conversational contract.

2. **Stable verb/evidence-packet surface**
   - bounded CLI commands and JSON packet schemas for Robut;
   - safe defaults, explicit semantics, provenance, drill-downs, and privacy/join policy;
   - normal chat should use this instead of improvised arbitrary SQL.

## Privacy, agency, and correction boundaries

- Location history is sensitive. Treat it as private evidence, not ambient context to be sprayed everywhere.
- Do not join Swarm data with cameras, calendar, Paprika, clime, messages, or other household data unless a query explicitly needs it or a documented policy allows it.
- If a source is included in a cross-source packet, explain why it was included and what it contributed.
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
- evidence-packet schema stability;
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
- `docs/` — focused contracts/specs that would bloat `AGENTS.md`, such as credential probe notes, schema docs, evidence packet schemas, Datasette/audit recipes, source API contracts, and migration decisions.

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
- a dashboard/workbench replaces the evidence API instead of sitting beside it.

## Working style for agents

- Start by reading `AGENTS.md`, `README.md`, `TODO.md` if present, and focused docs relevant to the task.
- For research-shaped work, check the Obsidian source notes listed above.
- Make the smallest coherent change that solves the real problem.
- Challenge scope drift kindly and directly.
- Keep code, schemas, command surfaces, and docs easy to inspect after time away.
- Prefer trade-off analysis over generic best-practice language.
- When uncertain, choose the narrower interpretation and ask before broadening scope.

## Final rule

Build the small thing that does its job clearly.

Do not build an empire.
