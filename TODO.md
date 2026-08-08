# TODO.md — swarm-cadence

Active backlog only. Completed work belongs in git history, tests, and release
notes. Durable architecture and constraints live in `AGENTS.md`; human usage
lives in `README.md`; focused contracts live in `Docs/`.

## Now

- [ ] Exercise the current evidence and annotation surfaces in real
  Almanac/Guide work.
  - Prefer the stable query verbs (`venues`, `visits`, `cadence`, `compare`, and
    `lapses`) over the experimental envelopes.
  - Use attached annotations for concrete, human-approved venue, category,
    geography, window, or context caveats.
  - Record repeated evidence gaps before adding another command, schema, or
    correction mechanism.

- [ ] Add descriptive trip / travel-burst clustering.
  - Keep clusters bounded by explicit dates, geography, and a visible gap rule.
  - Return dates, countries/localities, support, representative venues and
    categories, freshness, and drill-downs.
  - Keep local-versus-travel separation factual; do not infer travel style,
    preference, or significance.
  - Candidate shape:
    `query trips --country-code TW --gap-days 3 --format json`.

## Next, if real use justifies it

- [ ] Decide whether venue reconciliation needs anything beyond
  `audit identity` plus annotations.
  - Start from real duplicate, renamed, closed, category, or coordinate cases.
  - Prefer visible aliases/caveats over automatic merges or rewritten evidence.

- [ ] Consider transparent category groups if repeated exact `--category`
  selection remains cumbersome.
  - Groups must expand to concrete Foursquare categories in output.
  - Do not add fuzzy cuisine or preference models to the CLI.

- [ ] Retire or demote the experimental evidence envelopes once stable query
  pieces cover the real workflows.
  - `swarm-cadence` should expose source and derived evidence; Robut owns final
    evidence packets, Almanacs, Guides, and recommendations.

## Triggered contingencies

These are not active work:

- Implement the live `historysearch` fallback only if v2 becomes unusable for
  an account.
- Add richer correction application only if attached annotations prove
  insufficient in repeated real cases.
- Keep Paprika, weather, calendar, and other cross-source joins above this CLI
  and make each join boundary explicit.
