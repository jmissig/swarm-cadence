# Pattern Intelligence Proposal — swarm-cadence

## Thesis

`swarm-cadence` should be the local-first Swarm/Foursquare check-in evidence layer for Robut: preserve raw check-in history, normalize visits and venues, compute traceable/rebuildable derived observations, and support human-facing **Almanacs** and **Guides** without becoming a generic Foursquare SDK, social client, dashboard, or opaque recommender.

The near-term acceptance test is concrete:

> Julian asks: “Where should I grab lunch today?”

The next implementation move is a thin vertical slice, not “the connector”:

```text
source probe
  -> ingest or fixture enough Julian data
  -> produce a real Lunch Guide source bundle
  -> render static Lunch Guide option entries from that bundle
  -> add edits/corrections after the bundle shape is stable
```

## Source research notes

This proposal adapts the Obsidian research notes and artifacts:

- `Foursquare Swarm Connector` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Foursquare Swarm Connector.md`
- `Pattern Extraction Tooling` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Extraction Tooling.md`
- `Pattern Intelligence Research Index` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Intelligence Research Index.md`
- `Almanacs and Guides` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Almanacs and Guides.md`
- `Julian’s Food & Places Almanac v0` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Julian’s Food & Places Almanac v0.md`
- `Lunch Guide Source Bundle v0` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide Source Bundle v0.md`
- `Lunch Guide v0` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Lunch Guide v0.md`

## Vocabulary boundary

Tool-side docs may use precise implementation terms: source adapter, raw evidence DB, sidecar/model DB, evidence packet, provenance, drill-down, derived observation, correction record.

Human-facing artifacts should use friendlier terms:

- **Food & Places Almanac** — durable sourced understanding over time.
- **Lunch Guide** — situated help for “where should I grab lunch today?”
- **Lens** — reliable nearby, revive lapsed, quick, outing, rainy day, with Alice.
- **Option** — a possible place/venue with reasons.
- **Source trail** — how to inspect where the claim came from.
- **Edit** — human correction or policy override.

Implementation rule of thumb:

> Compute facts freely when they are traceable and rebuildable; change meaning only with human authority.

## Current state

The repo now has a minimal Swift Package CLI with dry `source probe` commands,
an explicit live v2 source probe, and conservative one-request raw v2
preservation. `AGENTS.md` carries durable architecture guidance; schema,
ingest, normalized SQLite evidence, and Lunch Guide source bundles are still
not implemented.

Implemented dry probe commands:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json
swarm-cadence source probe --account julian --adapter historysearch --format json
```

These commands inspect environment/config shape only, redact sensitive values, and report `network_performed: false`. They intentionally stop at `external_setup_required` until Julian provides v2 OAuth token material or Swarm web `historysearch` session material outside git.

Implemented live v2 probe:

```bash
swarm-cadence source probe --account julian --adapter v2 --format json --config ./.swarm-cadence.env --live
```

The live v2 probe performs one read-only `GET /v2/users/self/checkins` request
with `limit=1`, reports viability/status and sample field coverage, and writes
no evidence database or fixtures.

Implemented raw v2 preservation:

```bash
swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250
```

This command performs exactly one v2 check-ins request, defaults to `limit=250`,
fails above `limit=250`, writes one unmodified raw JSON response and one
adjacent manifest, and does not write SQLite.

The proposal below should guide the first real slice without encouraging a broad connector build.

## Desired architecture

```text
Swarm/Foursquare source
  -> source probe / adapter choice
  -> raw payload preservation
  -> normalized SQLite evidence store
  -> derived observations and provisional pattern findings
  -> Lunch Guide source bundle / other evidence packets
  -> Food & Places Almanac + Lunch Guide
  -> Edits/corrections and future bundles
```

Source paths should remain replaceable:

1. official/legacy v2 OAuth check-in history if available;
2. narrow Swarm web `historysearch` fallback if needed;
3. official export/takeout for bootstrap/backfill/reconciliation;
4. current Places APIs only for venue enrichment, not check-in history.

Do not build a broad connector before the source probe establishes which path is viable.

## Two sibling surfaces

### 1. SQLite / Datasette-style explore-audit surface

Purpose: let humans and trusted agents inspect the local evidence, debug ingest, and discover better questions.

Early useful facets:

- source coverage by account/source path;
- raw check-in counts and date ranges;
- venue coverage: IDs, names, categories, lat/lng, closed/renamed status where available;
- check-ins by local time, day, meal window, geography, and account;
- candidate lunch venues by support, recency, and lapsed status;
- correction records and their effects.

This surface may use ad hoc SQL for investigation. It should be read-only by default and should not become the normal Robut chat contract.

### 2. Stable verb / source-bundle surface

Purpose: provide bounded grounding for Robut and future Guides.

Early target commands are provisional but should aim at the Lunch Guide source bundle:

```bash
swarm-cadence source probe --account julian --format json
swarm-cadence ingest fixture --account julian --source ./fixtures/julian-checkins.json --db ./.tmp/swarm.sqlite
swarm-cadence query visits --account julian --venue-id VENUE_ID --since 2y --format json
swarm-cadence query lapses --account julian --since 2y --min-visits 3 --format json
swarm-cadence evidence lunch --account julian --near home --format json
```

The `evidence lunch` output is a builder-facing source bundle for the human-facing Lunch Guide. It should return options, support, uncertainty, source trails, and visible joins — not one final “best lunch.”

## Lunch Guide source bundle requirements

The first real bundle should support `Lunch Guide Source Bundle v0` and `Lunch Guide v0`.

Required fields:

- query/scenario: lunch, account, geography, window, mode/lens;
- source freshness and coverage;
- candidate options with stable venue identity;
- source trails / drill-down commands;
- support counts and denominators;
- first/last seen and gap/lapse facts;
- meal-window support;
- category/cuisine/place-lane confidence;
- visible joins included/excluded/ask-first;
- uncertainty and placeholders;
- edit/correction affordances.

Candidate lenses:

- reliable nearby;
- revive lapsed;
- quick/easy;
- coffee/bakery outing;
- destination-if-time;
- avoid recent repeats;
- not Mexican today;
- with Alice / ask-first shared context;
- rainy day / walking matters.

## Derived observations vs edits

`swarm-cadence` may compute and store traceable, rebuildable derived observations:

- repeated recent lunch-window visits;
- lapsed-but-historically-strong venue;
- active cuisine/place lane;
- likely convenience repeat;
- sparse/uncertain category metadata;
- current evidence window and support counts.

These should be marked as derived/model-authored with source trail and generated-at metadata.

Meaning-changing records require human authority:

- “convenience, not preference”;
- “still loved, just forgotten”;
- “do not suggest this for lunch”;
- “ask before joining Alice context”;
- “that venue is closed/renamed” when not independently sourced;
- “this is Alice’s preference, not Julian’s.”

Raw check-ins stay untouched. Edits/corrections apply visibly to future bundles and Guides.

## Recommended next slices

1. **Source probe**
   - decide viable ingest path for Julian;
   - redact credentials/secrets;
   - report available fields, date range, venue/category/location coverage.
2. **Fixture or minimal ingest**
   - enough data to populate the lunch scenario;
   - explicit placeholders where real source fields are missing;
   - no broad sync yet.
3. **Emit first `lunch` source bundle**
   - use the v0 bundle shape;
   - include source trails and uncertainty;
   - avoid scoring or recommendations until fields are stable.
4. **Generate static Lunch Guide entries**
   - generate Markdown/HTML option entries from the bundle;
   - show lenses and why options move.
5. **Add edit/correction storage**
   - proposed / human-approved / human-authored states;
   - scoped effects on future bundles;
   - raw evidence untouched.
6. **Add join mini-bundles later**
   - Paprika dinner/taste context;
   - `clime` outing/weather context;
   - explicit join-boundary table.

## Privacy and agency boundaries

- Location history is sensitive. Treat it as private evidence.
- Keep Julian and Alice accounts explicit and separate.
- Do not blend accounts or infer household/shared preferences unless explicitly scoped.
- Do not join Swarm with cameras, messages, calendar, Paprika, or `clime` unless the query or Guide makes that join visible and justified.
- Avoid stale identity claims. A 2018 favorite should not silently become a 2026 preference.
- Avoid moralizing or personality labels from check-ins.
- Check-ins show presence, not preference.

## Success test

A first implementation slice succeeds if it can:

- probe the source safely;
- produce a small real or fixture-backed Lunch Guide source bundle;
- render a static Lunch Guide from that bundle;
- show every option’s source trail;
- distinguish raw evidence, derived observation, proposed interpretation, and human edit;
- list missing queries/fields for the next slice.

If that works, `swarm-cadence` has a useful vertical seam. Only then should the project broaden into ongoing sync, richer modeling, joins, or correction UX.

## Connector source-path learnings

The Obsidian `Foursquare Swarm Connector` research note compared source paths and should be treated as the durable source-design background for this repo.

Decision criteria:

- ongoing ingest matters because Julian and Alice continue using Swarm;
- data completeness matters: check-in id, timestamp, venue id/name, location, photos when possible, and raw JSON for later modeling;
- credential practicality matters more than theoretical API cleanliness;
- multi-account separation is a first-order architecture constraint;
- local evidence should be queried locally, not repeatedly scraped/API-called for every Robut answer.

Recommended adapter order:

1. **v2 OAuth user check-ins** — best primary path if the credential probe proves it works.
   - Target endpoint: `GET /v2/users/self/checkins` for the token owner.
   - Test legacy query-param token and documented auth styles if needed.
   - Known risk: newer app/token paths may be gated or return `402 Payment Required`.
2. **Swarm web `historysearch`** — best fallback if v2 OAuth is blocked.
   - Uses logged-in Swarm web request/session parameters such as `userid`, `wsid`, and `oauth_token`.
   - Works in recent public tools, but is private/brittle and requires careful secret handling.
3. **Official export/takeout import** — bootstrap, backfill, and reconciliation only.
   - Useful and user-controlled, but not the primary ongoing sync path.
   - Export may omit fields such as venue coordinates, so enrichment/reconciliation may still be needed.
4. **User Push API / webhook** — possible phase 2 only.
   - Adds service/webhook operations that are unnecessary for the first connector.
5. **Current Places APIs** — venue enrichment only.
   - They are not a personal check-in history source.

Existing-project signals worth borrowing:

- `dogsheep/swarm-to-sqlite`: SQLite import, `--since`, Datasette-friendly local evidence precedent.
- `liskin/foursquare-swarm-ical`: maintained incremental SQLite sync pattern and token UX.
- `ericblue/swarm-downloader` and `jplaut/swarm-checkin-exporter`: current `historysearch` fallback examples.
- `lokesh/pinback` and Aaron Parecki / OwnYourSwarm tooling: recurring ingest and raw JSON/Micropub-style separation of backfill vs live export.
- `karlicoss/HPI`: export-file adapter as one source path, not the whole connector.

First `source probe` should answer:

1. Can Julian’s configured source read recent check-ins?
2. Can Alice’s configured source read recent check-ins?
3. Which adapter works for each account: v2 OAuth, `historysearch`, or export-only for now?
4. What fields are present/missing/source-specific?
5. Are secrets redacted and source/account provenance preserved in JSON output?

If v2 works, use `limit=250` as the largest documented conservative page size and test at least two offset pages before building broad backfill. If live evidence later proves a larger accepted cap, update the raw-fetch hard max deliberately. If v2 fails, test `historysearch` against a logged-in session and compare fields against export/takeout.
