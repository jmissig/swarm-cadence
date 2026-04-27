# TODO.md — swarm-cadence

Short active backlog only. Durable architecture and constraints live in `AGENTS.md`; pattern-intelligence direction lives in `docs/pattern-intelligence-proposal.md`.

## Next thin vertical slice

- [x] Bootstrap SwiftPM CLI and implement dry config-validation source probes.
  - `swarm-cadence source probe --account julian --adapter v2 --format json`
  - `swarm-cadence source probe --account julian --adapter historysearch --format json`
  - No network calls; reports `external_setup_required`; redacts configured values.
- [ ] Implement the explicit live credential probe after Julian completes external setup.
  - Determine whether v2 OAuth, Swarm web historysearch, or export/import is the viable initial source path.
  - Redact credentials and sensitive source details.
  - Report available fields: check-in IDs, venue IDs, categories, lat/lng, timestamps, account identity, date range, count.
- [ ] Create a fixture/minimal-ingest path for enough Julian check-in data to exercise the lunch scenario.
  - Use repo-local fixture/temp DB paths.
  - Mark fixture/placeholder fields explicitly.
- [ ] Emit a first `evidence lunch` / Lunch Guide source bundle JSON shape.
  - Follow `docs/pattern-intelligence-proposal.md` and Obsidian `Lunch Guide Source Bundle v0`.
  - Include options, source trails, support counts, uncertainty, visible joins, and correction affordances.
- [ ] Generate static Lunch Guide entries from the bundle.
  - Do not hand-copy option entries once the bundle exists.
  - Show lenses such as reliable nearby, revive lapsed, quick/easy, rainy day, with Alice/ask-first.
- [ ] Add correction/edit storage only after the source bundle shape is stable.
  - Store proposed / human-approved / human-authored states.
  - Keep raw check-ins untouched.

## Later

- [ ] Add ongoing ingest/backfill once the source path is proven.
- [ ] Add venue reconciliation: closed/renamed, aliases, categories, lat/lng confidence.
- [ ] Add derived observations: active anchors, lapsed favorites, meal-window support, gaps, geography clusters.
- [ ] Add Paprika and `clime` mini-bundles with explicit join boundaries.
- [ ] Add read-only SQLite/Datasette audit docs and canned inspection queries.

## Not now

- No full connector before the source probe.
- No generic Foursquare SDK.
- No write/sync-back to Swarm/Foursquare.
- No opaque recommender or hidden score.
- No silent Julian/Alice blending.
- No cross-source joins without a visible purpose and boundary.
