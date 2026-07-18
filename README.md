# swarm-cadence

`swarm-cadence` is a macOS command-line tool for preserving and querying a
private local copy of your Foursquare Swarm check-in history.

The repository also includes skills that help OpenClaw, ChatGPT, and Claude use
the tool to answer questions grounded in that history.

Use it to answer things like:

- “What coffee shops have I actually been to in Redwood City?”
- “When did I last go to this place?”
- “Which lunch spots have lots of history but no recent visits?”
- “Show me the evidence behind this place suggestion.”

The tool preserves raw source data locally, imports it into a rebuildable SQLite
DB, and exposes descriptive evidence queries. It does not write to Swarm, rate
places, infer favorites, or make recommendations by itself.

## Install

### Command-Line Tool

```bash
make install
swarm-cadence --version
```

That installs `swarm-cadence` to `~/bin/swarm-cadence` by default. If
`~/bin` is not already on your `PATH`, add it first.

To install elsewhere:

```bash
sudo make install PREFIX="/usr/local"
```

For development, use `make build` and `make test`. See
[docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md)
for deeper operator notes.

### Agent Skills

Install the repository's skill for OpenClaw (the default), Codex, or Claude
Code:

```bash
make install-skill ACCOUNTS="single-account"
make install-skill ACCOUNTS="single-account" SKILL_TARGET=codex
make install-skill ACCOUNTS="single-account" SKILL_TARGET=claude
```

Use `ACCOUNTS="single-account"` when the skill should use the CLI's sole
configured account without passing `--account`. To bake explicit account
choices into its examples instead, use the configured labels:

```bash
make install-skill ACCOUNTS="account1 account2"
```

The default destinations are:

- OpenClaw: `$OPENCLAW_HOME/skills/swarm-cadence`, with `OPENCLAW_HOME`
  defaulting to `~/.openclaw`
- Codex: `$CODEX_HOME/skills/swarm-cadence`, with `CODEX_HOME` defaulting to
  `~/.codex`
- Claude Code: `$CLAUDE_CONFIG_DIR/skills/swarm-cadence`, with
  `CLAUDE_CONFIG_DIR` defaulting to `~/.claude`

Set the corresponding home/config variable to install elsewhere. `SKILLS_DIR`
can also override the final skills directory directly.

## First Run

Create or update account auth interactively:

```bash
swarm-cadence auth login --account default
swarm-cadence auth status --account default --format json
```

Interactive terminals can guide missing auth values. JSON output, non-TTY
input, `--non-interactive`, and its `--no-input` alias never prompt; provide
`--account` and complete one-shot credential options instead.

Then check local readiness without touching credentials, raw payloads, SQLite
rows, or the network:

```bash
swarm-cadence source status --format json
```

Account labels are explicit (`default`, `partner`, or another configured label).
There is no silent account blending.

## A Few Useful Things

Pull in recent check-ins, then check the local evidence coverage:

```bash
swarm-cadence ingest --account default --adapter v2 --format json
swarm-cadence db stats --account default --format json
```

Ask what places the local history supports:

```bash
swarm-cadence query venues --account default --area peninsula --category "Coffee Shop" --format json
swarm-cadence query visits --account default --venue-id <venue-id> --format json
```

Compare broad history with recent activity:

```bash
swarm-cadence query compare --account default --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json
```

Import and audit commands, cadence/lapse rollups, source probes, and evidence
packet details are documented in
[docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md).

## How to Think About the Evidence

`swarm-cadence` reports visits and descriptive patterns; it does not decide
whether you liked a place or recommend where to go next.

Place wording stays literal. “In San Mateo” uses factual Foursquare locality
fields, while “near San Carlos” and named areas use configured geography that
may include nearby cities. Venue names and identities can also reflect later
Foursquare renames or merges rather than the exact historical label.

Annotations let you attach human-known caveats—such as a closure or former
name—without changing the preserved source evidence.

## Local Data

By default, account data lives under
`~/Library/Application Support/swarm-cadence/accounts/<account>/`, while config
and credentials live in
`~/Library/Application Support/swarm-cadence/config.json`. Raw responses are
preserved, and the SQLite database can be rebuilt from them and from file
imports.

## Related Docs

- [docs/operations-and-query-semantics.md](docs/operations-and-query-semantics.md) — detailed commands, query semantics, geography, and venue-identity caveats
- [docs/source-probe-setup.md](docs/source-probe-setup.md) — source setup, v2/historysearch probes, and schema notes
- [docs/pattern-intelligence-proposal.md](docs/pattern-intelligence-proposal.md) — boundary between evidence substrate and Robut-composed Almanac/Guide work
- [docs/pattern-boundary-and-corrections.md](docs/pattern-boundary-and-corrections.md) — annotations/corrections guidance and tool-boundary notes

---

Made with OpenClaw and Codex.
