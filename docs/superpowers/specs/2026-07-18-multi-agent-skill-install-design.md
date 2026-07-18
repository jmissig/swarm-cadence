# Multi-Agent Skill Install Design

## Goal

Let this repository install its bundled `swarm-cadence` skill into OpenClaw, Codex, or Claude Code using one Makefile target, while keeping OpenClaw as the default and preserving account-specific skill customization.

## Interface

`make install-skill` continues to require `ACCOUNTS` and accepts `SKILL_TARGET=openclaw|codex|claude`:

- `openclaw` installs to `$OPENCLAW_HOME/skills/swarm-cadence`, defaulting to `~/.openclaw/skills/swarm-cadence`.
- `codex` installs to `$CODEX_HOME/skills/swarm-cadence`, defaulting to `~/.codex/skills/swarm-cadence`.
- `claude` installs to `$CLAUDE_CONFIG_DIR/skills/swarm-cadence`, defaulting to `~/.claude/skills/swarm-cadence`.

The target-specific environment variable may override each default. `SKILLS_DIR` may override the resolved skills directory directly. An unsupported `SKILL_TARGET` fails with a clear Make error before any filesystem changes.

The existing install behavior remains otherwise unchanged: the repository skill directory is copied into the selected agent's skill root, account-specific examples are generated from `ACCOUNTS`, installable skill documentation is copied, and repository/install state is refreshed. The existing `.openclaw-skill-install.json` filename remains unchanged for compatibility; agent-neutral install metadata is outside this change.

## Documentation

The README will introduce `swarm-cadence` first as a macOS command-line tool for preserving and querying local Foursquare Swarm history. A separate lightweight sentence will then explain that the repository includes skills for OpenClaw, ChatGPT/Codex, and Claude.

The install section will keep binary installation primary, then provide a separate agent-skill subsection with one example for each target, the required `ACCOUNTS` forms, the default destination directories, and the corresponding override variables.

## Verification

Use Make dry runs with temporary target-specific homes to confirm all three destination paths and the account-customization step. Verify an unsupported target fails before running install commands. Perform real installs into temporary homes for each target and confirm the generated skill state and account-specific examples. Run `git diff --check` and the normal test suite before completion.

## Scope

Do not replace the existing account-aware installer, rename its compatibility metadata, add separate per-agent scripts, depend on another repository's installer, or introduce general package-manager behavior.
