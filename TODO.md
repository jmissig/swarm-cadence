# TODO.md — swarm-cadence

Active backlog only. Durable architecture and constraints live in `AGENTS.md`;
operator usage lives in `README.md`; source/probe contracts live in `docs/`.

## Next

- [ ] Add first evidence queries over the imported v2 SQLite sidecar.
  - Venue visit counts and first/last seen by account.
  - Date-window filters with explicit bounds in JSON output.
  - Lunch-window filters derived from stored check-in timestamps.
  - Drill-down descriptors that can reproduce supporting rows without printing
    raw payloads.
- [ ] Define the first Lunch Guide source bundle JSON shape.
  - Follow `docs/pattern-intelligence-proposal.md` and the Obsidian `Lunch Guide Source Bundle v0`.
  - Include account scope, freshness, support counts, uncertainty, source
    trails, and visible exclusions.
  - Keep the tool evidence-oriented; do not rank a hidden “best lunch.”
- [ ] Add account-aware query tests.
  - Separate Julian/Alice rows from the first query slice.
  - Cover JSON shape stability and count semantics.
  - Keep all tests fixture/temp-path only.
- [ ] Document the SQLite audit surface.
  - Add read-only inspection queries for coverage, date ranges, venues, and
    category completeness.
  - Keep ad hoc SQL as audit tooling, not the normal Robut contract.

## Later

- [ ] Add deliberate v2 paging/backfill once the evidence-query shape is useful.
- [ ] Add official export/takeout import for bootstrap, backfill, and
  reconciliation.
- [ ] Keep `historysearch` as a narrow fallback if v2 becomes blocked for an
  account.
- [ ] Add venue reconciliation: closed/renamed status, aliases, categories, and
  lat/lng confidence.
- [ ] Add derived observations: active anchors, lapsed favorites, meal-window
  support, gaps, and geography clusters.
- [ ] Add correction/edit storage after the source bundle shape is stable.
- [ ] Add Paprika and `clime` mini-bundles only with explicit join boundaries.

## Not Now

- No generic Foursquare SDK.
- No write/sync-back to Swarm/Foursquare.
- No hidden background sync.
- No opaque recommender or hidden score.
- No silent Julian/Alice blending.
- No cross-source joins without a visible purpose and boundary.
