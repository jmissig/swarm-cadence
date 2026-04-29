# Pattern Intelligence Proposal — swarm-cadence

## Thesis

`swarm-cadence` should be the local-first Swarm/Foursquare check-in evidence layer for Robut: preserve raw check-in history, normalize visits and venues, compute traceable/rebuildable derived observations, and support human-facing **Almanacs** and **Guides** without becoming a generic Foursquare SDK, social client, dashboard, or opaque recommender.

One near-term acceptance test is concrete:

> A person asks: “Where should I grab lunch today?”

Lunch is an example Guide to validate the theory, not the center of the tool. The next implementation move is a thin, reusable evidence-query slice, not “the connector,” not a lunch-specific recommender, and not a general-purpose packet/workbench generator:

```text
proven v2 path + preserved separate per-account raw pages
  -> parallel offline SQLite evidence stores with explicit account attribution
  -> first venue/date/window/cadence evidence queries
  -> stable source/derived pieces for Robut to compose
  -> static Guide option entries or Obsidian artifacts assembled above the CLI
  -> add edits/corrections after the source-piece shape is stable
```

## Source research notes

This proposal was adapted from private local research notes about Swarm/Foursquare
connectors, pattern extraction, Almanacs/Guides, and lunch/place evidence
artifacts. Those private note paths are intentionally not part of the public
repository.

## Vocabulary boundary

Tool-side docs may use precise implementation terms: source adapter, raw evidence DB, sidecar/model DB, source bundle, provenance, drill-down, derived observation, correction record. Use **evidence packet** for the Robut/LLM-composed decision artifact, not as the default name for every CLI output.

Human-facing artifacts should use friendlier terms:

- **Food & Places Almanac** — durable sourced understanding over time.
- **Lunch Guide** — situated help for “where should I grab lunch today?”
- **Lens** — reliable nearby, revive lapsed, quick, outing, rainy day, with another person.
- **Option** — a possible place/venue with reasons.
- **Source trail** — how to inspect where the claim came from.
- **Edit** — human correction or policy override.

Implementation rule of thumb:

> Compute facts freely when they are traceable and rebuildable; change meaning only with human authority.

## Current state

The repo now has a minimal Swift Package CLI with dry `source probe` commands,
an explicit live v2 source probe, conservative one-request raw v2 preservation,
and an offline GRDB/SQLite import for preserved v2 raw files. `AGENTS.md`
carries durable architecture guidance; Lunch Guide source bundles are still not
implemented.

Implemented dry probe commands:

```bash
swarm-cadence source probe --account default --adapter v2 --format json
swarm-cadence source probe --account default --adapter historysearch --format json
```

These commands inspect environment/config shape only, redact sensitive values, and report `network_performed: false`. They intentionally stop at `external_setup_required` until the operator provides v2 OAuth token material or Swarm web `historysearch` session material outside git.

Implemented live v2 probe:

```bash
swarm-cadence source probe --account default --adapter v2 --format json --live
```

The live v2 probe performs one read-only `GET /v2/users/self/checkins` request
with `limit=1`, reports viability/status and sample field coverage, and writes
no evidence database or fixtures.

Implemented raw v2 preservation:

```bash
swarm-cadence raw fetch --account default --adapter v2 --limit 250
```

This command performs exactly one v2 check-ins request, defaults to `limit=250`,
fails above `limit=250`, writes one unmodified raw JSON response and one
adjacent manifest, and does not write SQLite.

Implemented offline v2 SQLite import:

```bash
swarm-cadence db import-raw --account default
swarm-cadence db stats --account default
```

The importer performs no network calls, verifies raw SHA256 against adjacent
manifests, and builds small provenance-preserving `raw_files`, `checkins`,
`venues`, `categories`, and `checkin_categories` tables. The SQLite database is
a rebuildable query sidecar; preserved raw files remain the source of truth.

## Desired architecture

```text
Swarm/Foursquare source
  -> source probe / adapter choice
  -> raw payload preservation
  -> normalized SQLite evidence store
  -> derived observations and provisional pattern findings
  -> source/derived pieces for Robut-composed Guides
  -> Food & Places Almanac + Lunch Guide
  -> Edits/corrections and future bundles
```

Source paths should remain replaceable:

1. official/legacy v2 OAuth check-in history if available;
2. narrow Swarm web `historysearch` fallback if needed;
3. official export/takeout for bootstrap/backfill/reconciliation;
4. current Places APIs only for venue enrichment, not check-in history.

Do not turn the proven v2 path into a broad connector before the local evidence
queries and Lunch Guide bundle shape are useful.

## Two sibling surfaces

### 1. SQLite / Datasette-style explore-inspect surface

Purpose: let humans and trusted agents inspect the local evidence, debug ingest, and discover better questions.

Early useful facets:

- source coverage by account/source path;
- raw check-in counts and date ranges;
- venue coverage: IDs, names, categories, lat/lng, closed/renamed status where available;
- check-ins by local time, day, meal window, geography, and account;
- venue support by recency, windows, geography, and active/lapsed facts;
- human-annotations and where they attach.

This surface may use ad hoc SQL for investigation. It should be read-only by default and should not become the normal Robut chat contract.

### 2. Stable verb / evidence-substrate surface

Purpose: provide bounded grounding for Robut and future Guides without making `swarm-cadence` own the final answer, Robut evidence packet, or explorable interface.

Early target commands are provisional but should expose reusable evidence facts that Robut or a dedicated artifact layer can consume:

```bash
swarm-cadence source probe --account default --format json
swarm-cadence ingest fixture --account default --source ./fixtures/checkins.json --db ./.tmp/swarm.sqlite
swarm-cadence query visits --account default --venue-id VENUE_ID --from 2024-01-01 --format json
swarm-cadence query compare --account default --baseline-from 2024-01-01 --recent-from 2026-01-01 --hour-from 11 --hour-to 14 --format json
swarm-cadence evidence window --account default --date 2026-04-27 --hour-from 11 --hour-to 14 --format json
```

Guide-specific bundle/packet shaping happens above the reusable query layer. It should consume venue support, cadence, recency, uncertainty, and source trails — not hide a final “best” answer in `swarm-cadence`.

If the CLI keeps an experimental `evidence packet` command, treat it as a diagnostic/query envelope while the shape is being learned, not as the model every sibling tool must copy. The stable contract should be the smaller pieces: source rows, rollups, freshness, support counts, mechanical filter limits, and drill-down handles.

## Concrete Guide substrate requirements

The first real Guide artifact can use `Lunch Guide Source Bundle v0` and `Lunch Guide v0` as acceptance-test artifacts.

Required fields:

- query/scenario: lunch, account, geography, window, mode/lens;
- source freshness and coverage;
- venue options with stable identity as assembled above the CLI;
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
- with another person / ask-first shared context;
- rainy day / walking matters.

## Derived observations vs edits

`swarm-cadence` may compute and store traceable, rebuildable derived observations:

- repeated recent lunch-window visits;
- lapsed-but-historically-strong venue;
- category/time-window support facts;
- high-frequency or recent-repeat facts without preference meaning;
- sparse/uncertain category metadata;
- current evidence window and support counts.

These should be marked as derived/model-authored with source trail and generated-at metadata.

Meaning-changing records require human authority:

- “convenience, not preference”;
- “still loved, just forgotten”;
- “do not suggest this for lunch”;
- “ask before joining another person’s context”;
- “that venue is closed/renamed” when not independently sourced;
- “this is one person’s preference, not another’s.”

Raw check-ins stay untouched. Edits/corrections apply visibly to future bundles and Guides.

### Time semantics

Most Almanac-style pattern questions should be interpreted in the check-in's
experienced local time, not in a single caller-supplied timezone. For example,
an 08:00 hike in Hong Kong should count as a morning hike because it was morning
where the check-in happened. Likewise, “check-ins on 23 Dec” should normally
mean check-ins whose local calendar date was 23 Dec. This local-context lens
applies to hour-of-day, meal-window, weekday/weekend, day/month grouping, and
similar pattern facts.

Absolute instant slicing remains useful when explicitly requested, but it should
be separate from the default Almanac lens and named explicitly as UTC/instant
behavior. Normal query flags should not all repeat “local”; local check-in
calendar/time is the documented default, while UTC variants should say UTC in
the flag or command name. Fuzzy time concepts like “lunch” or “morning” should
belong to the LLM/Almanac layer as choices over explicit date/hour windows, not
as hidden presets inside the low-level evidence CLI. Future query work should decide how
to resolve experienced timezone from the fields we actually see:
`venue.timeZone`, with check-in `timeZoneOffset` as supporting/fallback evidence.
Do not add inference or audit machinery for missing timezone edge cases unless
missing data shows up as a real problem in actual outputs; a small amount of
missing or uncertain history is acceptable.

The sidecar should retain UTC `createdAt` as the canonical instant/provenance,
but materialize experienced local-time fields during import when timezone
evidence is available. This keeps timezone math in one inspectable ingest seam
and lets queries/almanacs read local date/hour/weekday facts without repeatedly
recomputing timezone behavior at runtime.

## Recommended next slices

1. **Evidence queries over imported v2 data**
   - current first slice: venue visit support, first/last seen, date ranges, explicit single-account scope, and source trails that reproduce supporting rows without printing raw payloads;
   - add explicit date/hour filters and generic cadence comparison facts (baseline vs recent support, last seen, lapse age);
   - later multi-account extension: explicit joint/family scopes, never implicit blending.
2. **Emit first reusable source/derived pieces for a concrete Guide example**
   - use the v0 Lunch artifacts as an acceptance test, while keeping the query layer generic;
   - include source trails and uncertainty;
   - avoid scoring or recommendations in the CLI.
3. **Generate static Guide entries above the CLI**
   - generate Markdown/HTML option entries from the pieces;
   - show lenses and why options move.
4. **Add edit/correction storage**
   - proposed / human-approved / human-authored states;
   - scoped effects on future bundles;
   - raw evidence untouched.
5. **Add join mini-bundles later**
   - Paprika dinner/taste context;
   - `clime` outing/weather context;
   - explicit join-boundary table.

## Privacy and agency boundaries

- Location history is sensitive. Treat it as private evidence.
- Keep multiple people accounts explicit and separate.
- Do not blend accounts or infer household/shared preferences unless explicitly scoped.
- Do not join Swarm with cameras, messages, calendar, Paprika, or `clime` unless the query or Guide makes that join visible and justified.
- Avoid stale identity claims. A 2018 favorite should not silently become a 2026 preference.
- Avoid moralizing or personality labels from check-ins.
- Check-ins show presence, not preference.

## Success test

A first implementation slice succeeds if it can:

- use preserved v2 evidence without live network calls;
- produce small real Guide-ready source/derived outputs from reusable evidence queries;
- let Robut or a script render a static Guide from those pieces;
- show every option’s source trail;
- distinguish raw evidence, derived observation, proposed interpretation, and human edit;
- list missing queries/fields for the next slice.

If that works, `swarm-cadence` has a useful vertical seam. Only then should the project broaden into ongoing sync, richer modeling, joins, or correction UX.

## Connector source-path learnings

The Obsidian `Foursquare Swarm Connector` research note compared source paths and should be treated as the durable source-design background for this repo.

Decision criteria:

- ongoing ingest matters because multiple people continue using Swarm;
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

1. Can the first configured source read recent check-ins?
2. Can the second configured source read recent check-ins?
3. Which adapter works for each account: v2 OAuth, `historysearch`, or export-only for now?
4. What fields are present/missing/source-specific?
5. Are secrets redacted and source/account provenance preserved in JSON output?

If v2 works, use `limit=250` as the largest documented conservative page size and test at least two offset pages before building broad backfill. If live evidence later proves a larger accepted cap, update the raw-fetch hard max deliberately. If v2 fails, test `historysearch` against a logged-in session and compare fields against export/takeout.
