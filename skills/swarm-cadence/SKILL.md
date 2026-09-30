---
name: swarm-cadence
description: Query local Foursquare Swarm history for visited places, venue patterns, categories, geography, and freshness. Use for history-grounded place questions, not live hours or open-now discovery.
---

# swarm-cadence

Use local Foursquare Swarm evidence to answer questions about visited places, venue patterns, categories, geography, and freshness.

`swarm-cadence` provides evidence; the agent composes the answer and distinguishes observations from interpretation.

---

## Safety and scope

- Queries read local evidence. Ingest writes local raw files and SQLite; annotations write local interpretive context. None of these writes to Swarm/Foursquare.
- Keep `--account` explicit (`default`, `partner`, or a configured label). Do not silently blend accounts.
- When account scope is unclear or multiple people are possible, run `swarm-cadence source status --format json` first, then use an explicit `--account`.
- Treat check-ins as evidence of visits, not proof of preference.
- Keep facts separate from inference; surface uncertainty and stale data.
- Use explicit windows, categories, and geography. Do not invent fuzzy filters inside the CLI.
- Prefer JSON for tool/agent work; summarize in friendly Guide/Almanac language for humans.

Foundation chooses the app-support base. The app root is
`~/Library/Application Support/swarm-cadence` on macOS and
`$XDG_DATA_HOME/swarm-cadence` (default `~/.local/share/swarm-cadence`) on Linux.
`SWARM_CADENCE_APP_SUPPORT_DIR` overrides that complete app root; explicit CLI
path options take precedence.

```text
<app-root>/config.json
<app-root>/accounts/<account>/swarm-cadence.sqlite
<app-root>/accounts/<account>/raw/v2/checkins
```

---

## Core commands

```bash
swarm-cadence source status --format json
swarm-cadence auth status --account default --format json
swarm-cadence db stats --account default --format json
swarm-cadence query categories --account default --format json
swarm-cadence query venues --account default --format json
swarm-cadence query visits --account default --venue-id <venue-id> --format json
swarm-cadence query cadence --account default --venue-id <venue-id> --from 2024-01-01 --format json
swarm-cadence query compare --account default --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
swarm-cadence query lapses --account default --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
```

Use `swarm-cadence --help` for the current surface.

---

## Freshness policy

For substantive answers, check freshness from `db stats`:

- `last_fetched_at_iso8601`: latest raw source pull
- `last_imported_at_iso8601`: latest import into SQLite
- `current_through_iso8601`: latest imported check-in timestamp
- `oldest_created_at_iso8601` / `latest_created_at_iso8601`: evidence coverage window

If freshness is missing, stale, or much older than the user’s question, say so before interpreting. Do not imply current open/closed status, hours, or today’s availability from Swarm alone.

Use `ingest` only when the user asks for a refresh or the workflow explicitly calls for one; it is read-only against Swarm/Foursquare but writes local raw files and SQLite.

```bash
swarm-cadence ingest --account default --adapter v2 --format json
```

---

## Category selection

When the user asks for a kind of place, inspect categories before querying:

```bash
swarm-cadence query categories --account default --format json
```

Choose explicit Foursquare category names and pass them with repeated `--category` flags. Examples:

- coffee: `--category "Coffee Shop" --category "Café"`
- lunch/food broad pass: start with a few explicit categories relevant to the prompt, not every restaurant category
- Mexican: `--category "Mexican Restaurant"`

Surface selected categories in the answer. Category filters are exact, case-insensitive Foursquare category evidence; they are not fuzzy cuisine inference.

---

## Geography

Do not flatten place language:

- “in San Carlos” → factual locality filters, e.g. `--locality "San Carlos" --region CA --country-code US`
- “near San Carlos” → an anchor representing San Carlos plus a radius: use `--near-place <configured-anchor> --radius-meters 7000` if that anchor exists, or `--near-lat ... --near-lng ... --radius-meters ...` with established coordinates. Do not substitute `home` for the requested place.
- “San Carlos / Redwood City area” → named factual area, e.g. `--area peninsula`, when the local config defines the area.

Prefer named geography when available because it keeps repeated Almanac/Guide
queries consistent. Still surface the resolved definition in the answer:
anchor name, radius, included localities, and the `geography.semantics` string.
Do not treat named geography as fuzzy inference. Distance is evidence, not
judgment. If using an anchor/radius, say that the radius can include nearby
localities.

---

## Evidence views and sorting

`query venues`, `query cadence`, and `query compare` support:

```bash
--sort nearest|strongest|recent|stale
```

- `nearest`: closest first; requires a configured `--near-place` anchor with a configured or explicit radius, or explicit `--near-lat --near-lng --radius-meters`
- `strongest`: most visit support first
- `recent`: most recently visited first
- `stale`: stale/lapsed evidence first

Use `query cadence` when the answer needs venue-level time patterns: first/last seen, local-hour buckets, ISO weekday buckets, weekday/weekend counts, observed gaps, freshness, and visit drill-downs. These are descriptive facts, not meal labels or recommendations.

Use `query lapses` for active/lapsed venue evidence across baseline/recent windows. It exposes support counts, days since last visit, observed gaps, and drill-downs—not reasons for a lapse or changed preferences.

`evidence packet` is an experimental diagnostic envelope, not the default answer workflow. Prefer stable queries and compose the answer in the agent; use the envelope only when inspecting its combined views is useful.

---

## Typical answer workflow

1. Pick account and scope. If unclear, run `source status` first.
2. Check freshness and coverage with `db stats`.
3. For place-type questions, run `query categories` and select explicit categories.
4. Choose geography semantics (`locality`, named `area`, or anchor/radius).
5. Use `query venues` for matching places, `query visits` for supporting visits, `query cadence` for time patterns, or `query compare` / `query lapses` for baseline/recent comparisons. Follow returned drill-downs when individual records matter.
6. If the stable CLI verbs are too slow or too narrow for schema/coverage/debugging exploration, read `docs/readonly-sqlite-exploration.md` in this installed skill and use its read-only SQLite workflow. Prefer this for Datasette-style inspection, not normal human answers.
7. Answer in human terms:
   - summarize the most relevant evidence views
   - mention freshness and selected categories/geography
   - separate observed facts from inferred suggestions
   - mention limitations only where they materially affect the answer

The answer is complete when it addresses the question with supporting evidence, identifies the account and relevant scope/freshness, and distinguishes findings from gaps. A successful command alone is not an answer.

## Missing or surprising results

- Missing database or unconfigured account: use `source status` to inspect account/path availability. Report what is missing; do not silently initialize, import, or refresh data.
- Ambiguous account: status can list labels but cannot decide which person the user meant. Resolve the intended account before interpreting results.
- Successful query with zero matches: check the account, date window, category names, geography, and source coverage. Report “no matching records in this scope,” not “never visited.”
- Failed command: inspect its error and relevant subcommand `--help`; do not present failure as an empty result. If unresolved, report the concrete blocker and any usable partial evidence.

---

## Direct SQLite exploration

The installed skill includes `docs/readonly-sqlite-exploration.md`. Use it only when direct SQL will materially speed up inspection or debugging beyond the stable CLI surface.

Good reasons to use it:

- inspect schema or table/column availability
- check coverage, row counts, date ranges, or category completeness
- sample evidence carefully to understand source quirks
- debug a surprising CLI result
- prototype a repeated query shape before promoting it to a stable command

Rules:

- open SQLite with `sqlite3 -readonly` and `PRAGMA query_only = ON`
- always scope by account unless intentionally comparing accounts
- keep `LIMIT` on exploratory row queries
- prefer normalized columns before reading `raw_json`
- never mutate tables, annotations, schema, or raw evidence
- report direct SQL findings as read-only inspection, with caveats and source freshness

Do not use direct SQL to create hidden recommendation scores or bypass the CLI's account/provenance/freshness semantics in normal answers.

---

## Durable interpretive context / annotations

When human feedback would materially change future interpretation—such as a duplicate venue, accidental check-in, or misleading category—offer to remember it as an annotation. Casual commentary is not authorization to persist it. An explicit request to add or remember a Swarm annotation already authorizes the write; do not ask again. Resolve any missing account or target first.

Attach plain-English context rather than changing source evidence:

```bash
swarm-cadence annotations add \
  --account default \
  --target-kind venue \
  --target-id <venue-id> \
  --body "This venue is a duplicate/old identity for <current venue>; treat historical check-ins as support for the current place, not a separate option." \
  --source human
```

Use `annotations kinds` to discover allowed target kinds, and `annotations targets` to reuse local target-id conventions before inventing a new one. Annotations are attached context, not source evidence, ratings, favorites, or recommendations.

After adding one, verify the returned annotation's account, target, and body before reporting it saved.

---

## Boundaries

Do not use `swarm-cadence` for:

- live business hours or open-now status
- writing/editing Swarm/Foursquare data
- hidden recommendation scores
- cross-source joins unless the user asks or the task clearly needs them
- silently inferring personal preference from a single visit

When the evidence looks misleading, say what gap showed up: stale venue, duplicate/renamed venue, weak category coverage, sparse history, or missing current context.
