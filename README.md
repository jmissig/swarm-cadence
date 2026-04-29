# swarm-cadence

`swarm-cadence` lets you keep a private local copy of your Foursquare Swarm
check-in history and ask simple questions about it later.

Use it to answer things like:

- “What coffee shops have I actually been to in Redwood City?”
- “When did I last go to this place?”
- “Which lunch spots have lots of history but no recent visits?”
- “Show me the evidence behind this place suggestion.”

The tool preserves raw source data locally, imports it into a rebuildable SQLite
DB, and exposes descriptive evidence queries. It does not write to Swarm, rate
places, infer favorites, or make recommendations by itself.

## Install

```bash
make install
swarm-cadence --version
```

For development, use `make build` and `make test`. See
[docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md)
for deeper operator notes.

## First Run

Create or update account auth interactively:

```bash
swarm-cadence auth login --account julian
swarm-cadence auth status --account julian --format json
```

Then check local readiness without touching credentials, raw payloads, SQLite
rows, or the network:

```bash
swarm-cadence source status --format json
```

Account labels are explicit (`julian`, `alice`, or another configured label).
There is no silent account blending.

## A Few Useful Things

Pull in recent check-ins, then check the local evidence coverage:

```bash
swarm-cadence ingest --account julian --adapter v2 --format json
swarm-cadence db stats --account julian --format json
```

Ask what places the local history supports:

```bash
swarm-cadence query venues --account julian --area peninsula --category "Coffee Shop" --format json
swarm-cadence query visits --account julian --venue-id <venue-id> --format json
```

Compare broad history with recent activity:

```bash
swarm-cadence query compare --account julian --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
```

Import and audit commands, cadence/lapse rollups, source probes, and evidence
packet details are documented in
[docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md).

## Geography and Evidence Semantics

Place wording matters:

```bash
# "in San Mateo" — factual Foursquare venue locality fields
swarm-cadence query venues --account julian --locality "San Mateo" --region CA --country-code US --format json

# "near San Carlos" — geometry around an anchor, allowing nearby cities too
swarm-cadence query venues --account julian --near-lat 37.5072 --near-lng -122.2605 --radius-meters 7000 --format json

# named presets from config
swarm-cadence query venues --account julian --near-place jackson-square --radius-meters 900 --format json
swarm-cadence query venues --account julian --area peninsula --category "Coffee Shop" --format json
```

Foursquare venue identity can be retrospective: old check-ins may come back from
the API with a current venue name/identity after upstream renames or merges.
Treat venue names as current/source identity evidence, not perfect historical
labels. Use annotations for durable human-known caveats such as “this was the
old Bliss Coffee spot, later Red Giant Coffee, now closed.”

## Annotations

Annotations are sidecar interpretive context attached to evidence targets. They
are not source rows, derived facts, ratings, favorites, or recommendations.

```bash
swarm-cadence annotations kinds --format json
swarm-cadence annotations targets --account julian --format json
swarm-cadence annotations add \
  --account julian \
  --target-kind venue \
  --target-id <venue-id> \
  --body "This venue is closed; treat historical check-ins as closed-venue evidence, not a current place option." \
  --source human
swarm-cadence annotations list --account julian --target-kind venue --target-id <venue-id> --format json
```

Inline annotations are included by default where query outputs naturally
encounter their targets. Use `--no-annotations` on supported query commands to
omit them.

## What Lives Where

- Raw preserved responses and local SQLite DBs live under
  `~/Library/Application Support/swarm-cadence/accounts/<account>/` by default.
- Config and private credentials live under
  `~/Library/Application Support/swarm-cadence/config.json`.
- Checked-in `data/` and generated raw payloads should stay out of git.
- The SQLite DB is rebuildable from preserved raw evidence and file imports.
- Prefer `--format json` for scripts and agents; `--json` is accepted as a
  shorthand where supported.

## Safety Boundaries

- Keep tokens, cookies, browser-session details, raw payloads, and SQLite files
  out of git.
- Use explicit `--account` for non-login commands.
- Use `--config`, `--db`, `--raw-dir`, and `--out` when overriding defaults.
- Do not run `--live`, `raw fetch`, or `ingest` as routine tests.
- Do not use one account's credentials for another account label.
- Treat check-ins as evidence of visits, not proof of preference.
- Treat open-now status, current hours, recommendations, and cross-source joins
  as Robut/Guide-layer concerns unless explicitly handled elsewhere.

## Related Docs

- [docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md) — detailed commands, query semantics, geography, and venue-identity caveats
- [docs/source-probe-setup.md](docs/source-probe-setup.md) — source setup, v2/historysearch probes, and schema notes
- [docs/pattern-intelligence-proposal.md](docs/pattern-intelligence-proposal.md) — boundary between evidence substrate and Robut-composed Almanac/Guide work
- [docs/pattern-boundary-and-corrections.md](docs/pattern-boundary-and-corrections.md) — annotations/corrections guidance and tool-boundary notes
