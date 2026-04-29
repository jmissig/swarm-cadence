---
name: swarm-cadence
description: Local read/query access to Foursquare Swarm check-in evidence for places, venue history, category support, local geography, freshness, and Almanac/Guide-style food/place questions.
---

# swarm-cadence

Local, read-only evidence tool for Foursquare Swarm check-in history. Use it when answering questions about places a configured account has visited, local venue support, coffee/lunch/place options, category history, geography-bounded patterns, or freshness of Swarm evidence.

`swarm-cadence` provides evidence, not recommendations. Robut chooses the human framing.

---

## Safety and scope

- Read/query local evidence first; do not write to Swarm/Foursquare.
- Keep `--account` explicit (`default`, `partner`, or a configured label). Do not silently blend accounts.
- When account scope is unclear or multiple people are possible, run `swarm-cadence source status --format json` first, then use an explicit `--account`.
- Treat check-ins as evidence of visits, not proof of preference.
- Keep facts separate from inference; surface uncertainty and stale data.
- Use explicit windows, categories, and geography. Do not invent fuzzy filters inside the CLI.
- Prefer JSON for tool/agent work; summarize in friendly Guide/Almanac language for humans.

Default local paths:

```text
~/Library/Application Support/swarm-cadence/config.json
~/Library/Application Support/swarm-cadence/accounts/<account>/swarm-cadence.sqlite
~/Library/Application Support/swarm-cadence/accounts/<account>/raw/v2/checkins
```

---

## Core commands

```bash
swarm-cadence source status --format json
swarm-cadence auth status --account default --format json
swarm-cadence db stats --account default --format json
swarm-cadence ingest --account default --adapter v2 --format json
swarm-cadence query categories --account default --format json
swarm-cadence query venues --account default --format json
swarm-cadence query visits --account default --venue-id <venue-id> --format json
swarm-cadence query cadence --account default --venue-id <venue-id> --from 2024-01-01 --format json
swarm-cadence query compare --account default --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
swarm-cadence evidence packet --account default --date 2026-04-27 --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
```

Use `swarm-cadence --help` for the current surface.

---

## Freshness policy

For substantive answers, check freshness from `db stats` or `evidence packet`:

- `last_fetched_at_iso8601`: latest raw source pull
- `last_imported_at_iso8601`: latest import into SQLite
- `current_through_iso8601`: latest imported check-in timestamp
- `oldest_created_at_iso8601` / `latest_created_at_iso8601`: evidence coverage window

If freshness is missing, stale, or much older than the user’s question, say so before interpreting. Do not imply current open/closed status, hours, or today’s availability from Swarm alone.

Use `ingest` only when the user asks for a refresh or the workflow explicitly calls for one; it is read-only against Swarm/Foursquare but writes local raw files and SQLite.

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
- “near San Carlos” → named or caller-supplied anchor/radius, e.g. `--near-place home --radius-meters 7000` or `--near-lat ... --near-lng ... --radius-meters ...`
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

- `nearest`: closest first; requires `--near-lat --near-lng --radius-meters`
- `strongest`: most visit support first
- `recent`: most recently visited first
- `stale`: stale/lapsed evidence first

Use `query cadence` when the answer needs venue-level time patterns: first/last seen, local-hour buckets, ISO weekday buckets, weekday/weekend counts, observed gaps, freshness, and visit drill-downs. These are descriptive facts, not meal labels or recommendations.

Use `query lapses` when the answer is specifically about active/lapsed venue evidence across baseline/recent windows. It is a factual wrapper over comparison evidence: support counts, days since last visit, observed gaps, freshness, geography, categories, and drill-downs. Do not translate lapse evidence into “disliked,” “abandoned,” “favorite,” or a hidden recommendation without clearly adding Robut-level caveats above the tool output.

Evidence packets include labeled views (`strongest`, `recent`, `stale`, and `nearest` when geography is present). Use the view labels when explaining results; do not describe a list as “best” unless you add your own caveated human judgment above the evidence.

---

## Typical answer workflow

1. Pick account and scope. If unclear, run `source status` first.
2. Check `db stats` / packet freshness.
3. For place-type questions, run `query categories` and select explicit categories.
4. Choose geography semantics (`locality`, named `area`, or anchor/radius).
5. Run `evidence packet` for multi-view evidence, `query cadence` for venue time-pattern rollups, `query lapses` for active/lapsed comparison evidence, or lower-level `query venues` / `query compare` for narrower debugging.
6. Answer in human terms:
   - summarize the most relevant evidence views
   - mention freshness and selected categories/geography
   - separate observed facts from inferred suggestions
   - include caveats for stale venues, old one-off visits, missing open-now data, or category mismatch

Good answer shape:

```text
I checked Swarm evidence through <date>. For coffee near San Carlos, using Coffee Shop/Café within ~6 km of the anchor, the evidence splits this way: strongest historical support ..., nearest ..., recent .... I’d treat this as visit-history evidence, not open-now/current-quality data.
```

---

## Durable interpretive context / annotations

If a human gives feedback, corrections, or commentary that would materially change how future tool users should interpret Swarm evidence, pause and ask whether they want that context remembered durably as an annotation.

This applies especially to commentary about:

- a venue: renamed, closed, duplicate, wrong identity, misleading category, or “this check-in was really for the place next door”
- a check-in: accidental, imported wrong, private/irrelevant, unusual context, or not representative of a real visit pattern
- a category: too broad/narrow, locally misleading, or not useful for a specific kind of question
- geography: local radius assumptions, neighborhood boundaries, travel corridors, or “near X” conventions
- context/window: family context, recurring situation, time-bounded caveat, or interpretation rule for a class of future questions

Ask plainly, using memory/durability/annotation language rather than generic “save this?” phrasing. Good examples:

```text
That changes how I’d interpret this evidence later. Should I remember it as a Swarm annotation?
```

```text
Should I add that as durable commentary on this venue/check-in/category?
```

```text
Want me to attach that as an annotation so future Swarm lookups see the caveat?
```

If the human approves, attach an annotation rather than changing source evidence or creating recommendation/preference machinery. Keep the body plain-English and interpretive:

```bash
swarm-cadence annotations add \
  --account default \
  --target-kind venue \
  --target-id <venue-id> \
  --body "This venue is a duplicate/old identity for <current venue>; treat historical check-ins as support for the current place, not a separate option." \
  --source human
```

Use `annotations kinds` to discover allowed target kinds, and `annotations targets` to reuse local target-id conventions before inventing a new one. Annotations are attached context, not source evidence, ratings, favorites, or recommendations.

---

## Boundaries

Do not use `swarm-cadence` for:

- live business hours or open-now status
- writing/editing Swarm/Foursquare data
- hidden recommendation scores
- cross-source joins unless the user asks or the task clearly needs them
- silently inferring personal preference from a single visit

When the evidence looks misleading, say what gap showed up: stale venue, duplicate/renamed venue, weak category coverage, sparse history, or missing current context.

<!-- repo-version: 0.6.0 -->
