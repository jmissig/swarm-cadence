# TODO.md — swarm-cadence

Short active backlog only. Durable architecture and constraints live in `AGENTS.md`; pattern-intelligence direction lives in `docs/pattern-intelligence-proposal.md`.

## Next thin vertical slice

- [x] Bootstrap SwiftPM CLI and implement dry config-validation source probes.
  - `swarm-cadence source probe --account julian --adapter v2 --format json`
  - `swarm-cadence source probe --account julian --adapter historysearch --format json`
  - No network calls; reports `external_setup_required`; redacts configured values.
- [x] Implement the explicit live v2 credential probe after Julian completes external setup.
  - `swarm-cadence source probe --account julian --adapter v2 --format json --config ./.swarm-cadence.env --live`
  - Performs one read-only `GET /v2/users/self/checkins` request with `limit=1`.
  - Redacts credentials and sensitive source details.
  - Reports source viability plus sample field coverage for check-in id, timestamp, venue id/name, lat/lng, categories, photos, and count/date hints.
- [x] Add conservative raw preservation for the proven v2 path.
  - `swarm-cadence raw fetch --account julian --adapter v2 --config ./.swarm-cadence.env --out data/raw/v2/checkins --limit 250`
  - Performs exactly one read-only `GET /v2/users/self/checkins` request per invocation.
  - Defaults to `limit=250` and `offset=0`; fails above the hard max limit of `250` or below offset `0`.
  - Writes one unmodified `*.raw.json` response plus one redacted adjacent manifest; no SQLite writes.
- [ ] Use the live v2 probe result to choose the next source path.
  - If v2 succeeds, build the smallest normalized SQLite slice around preserved v2 raw files.
  - If v2 is gated, unauthorized, or payment-required, implement the narrow live `historysearch` fallback.
  - Keep export/import available for bootstrap/backfill/reconciliation.
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
