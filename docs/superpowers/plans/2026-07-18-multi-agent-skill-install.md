# Multi-Agent Skill Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `make install-skill` target OpenClaw, Codex, or Claude Code while keeping account-aware skill generation and presenting `swarm-cadence` as a macOS CLI before describing its bundled agent skills.

**Architecture:** Keep installation in the existing Makefile and account customization in `scripts/install_skill.py`. Resolve one `SKILLS_DIR` from `SKILL_TARGET`, reuse the existing copy/customization recipe, and document the target-specific commands and paths in `README.md`.

**Tech Stack:** GNU Make, Python 3 installer helper, Markdown, Swift Package Manager verification

## Global Constraints

- OpenClaw remains the default target.
- Supported values are exactly `openclaw`, `codex`, and `claude`.
- `ACCOUNTS="single-account"` and whitespace-separated named accounts keep their current behavior.
- Preserve `.openclaw-skill-install.json` for compatibility.
- Do not replace `scripts/install_skill.py`, add per-agent scripts, or depend on another repository's installer.
- Do not modify or commit the pre-existing `AGENTS.md` worktree changes.

---

### Task 1: Add target-aware skill installation

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `SKILL_TARGET`, `OPENCLAW_HOME`, `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `SKILLS_DIR`, and the existing `ACCOUNTS` argument
- Produces: `SKILL_DEST=$(SKILLS_DIR)/swarm-cadence` for the selected agent

- [x] **Step 1: Verify unsupported target selection currently fails the desired contract**

Run:

```bash
make -n install-skill ACCOUNTS="single-account" SKILL_TARGET=invalid
```

Expected before implementation: exit 0 and output still targets the OpenClaw skill directory, demonstrating that `SKILL_TARGET` is ignored.

- [x] **Step 2: Add target resolution to the Makefile**

Replace the current OpenClaw-only variables with:

```make
SKILL_TARGET ?= openclaw
OPENCLAW_HOME ?= $(HOME)/.openclaw
CODEX_HOME ?= $(HOME)/.codex
CLAUDE_CONFIG_DIR ?= $(HOME)/.claude

ifeq ($(SKILL_TARGET),openclaw)
SKILLS_DIR ?= $(OPENCLAW_HOME)/skills
else ifeq ($(SKILL_TARGET),codex)
SKILLS_DIR ?= $(CODEX_HOME)/skills
else ifeq ($(SKILL_TARGET),claude)
SKILLS_DIR ?= $(CLAUDE_CONFIG_DIR)/skills
else
$(error Unsupported SKILL_TARGET '$(SKILL_TARGET)'; expected openclaw, codex, or claude)
endif

SKILL_DEST := $(SKILLS_DIR)/$(SKILL_NAME)
```

In `install-skill`, create `$(SKILLS_DIR)` instead of `$(OPENCLAW_SKILLS_DIR)` and finish with:

```make
	@echo "Installed skill $(SKILL_NAME) for $(SKILL_TARGET) to $(SKILL_DEST)"
```

- [x] **Step 3: Verify target path resolution and rejection**

Run:

```bash
make -n install-skill ACCOUNTS="single-account" SKILL_TARGET=openclaw OPENCLAW_HOME=/tmp/swarm-openclaw
make -n install-skill ACCOUNTS="single-account" SKILL_TARGET=codex CODEX_HOME=/tmp/swarm-codex
make -n install-skill ACCOUNTS="single-account" SKILL_TARGET=claude CLAUDE_CONFIG_DIR=/tmp/swarm-claude
make -n install-skill ACCOUNTS="single-account" SKILL_TARGET=invalid
```

Expected: the first three dry runs target `/tmp/swarm-{agent}/skills/swarm-cadence`; the fourth exits nonzero with `Unsupported SKILL_TARGET` before printing install commands.

- [x] **Step 4: Perform isolated installs for all targets**

Run:

```bash
TEST_ROOT=$(mktemp -d /tmp/swarm-cadence-skill-install.XXXXXX)
make install-skill ACCOUNTS="single-account" SKILL_TARGET=openclaw OPENCLAW_HOME="$TEST_ROOT/openclaw"
make install-skill ACCOUNTS="single-account" SKILL_TARGET=codex CODEX_HOME="$TEST_ROOT/codex"
make install-skill ACCOUNTS="single-account" SKILL_TARGET=claude CLAUDE_CONFIG_DIR="$TEST_ROOT/claude"
for agent in openclaw codex claude; do
  test -f "$TEST_ROOT/$agent/skills/swarm-cadence/SKILL.md"
  test -f "$TEST_ROOT/$agent/skills/swarm-cadence/.openclaw-skill-install.json"
  grep -F 'installed for a single configured account' "$TEST_ROOT/$agent/skills/swarm-cadence/SKILL.md"
done
```

Expected: all assertions pass and no real agent skill directory is touched.

- [x] **Step 5: Commit target-aware installation**

```bash
git add Makefile
git commit -m "Support multi-agent skill installation"
```

### Task 2: Separate CLI and agent-skill onboarding

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the Makefile interface from Task 1
- Produces: public macOS CLI introduction plus OpenClaw, Codex, and Claude Code skill installation instructions

- [x] **Step 1: Verify the README does not yet document all targets**

Run:

```bash
rg -n 'macOS command-line tool|SKILL_TARGET=codex|SKILL_TARGET=claude|CODEX_HOME|CLAUDE_CONFIG_DIR' README.md
```

Expected before implementation: no matches.

- [x] **Step 2: Rewrite the lightweight introduction**

Begin the README with these two distinct ideas:

```markdown
`swarm-cadence` is a macOS command-line tool for preserving and querying a private local copy of your Foursquare Swarm check-in history.

The repository also includes skills that help OpenClaw, ChatGPT, and Claude use the tool to answer questions grounded in that history.
```

Keep the existing task examples and evidence-boundary explanation after this introduction.

- [x] **Step 3: Document binary and agent-skill installation separately**

Keep `make install` first. Add an `### Agent Skills` subsection showing:

```bash
make install-skill ACCOUNTS="single-account"
make install-skill ACCOUNTS="single-account" SKILL_TARGET=codex
make install-skill ACCOUNTS="single-account" SKILL_TARGET=claude
```

Explain that `ACCOUNTS="account1 account2"` installs named-account examples. List the default destinations and overrides:

- OpenClaw: `$OPENCLAW_HOME/skills/swarm-cadence`, default `~/.openclaw`
- Codex: `$CODEX_HOME/skills/swarm-cadence`, default `~/.codex`
- Claude Code: `$CLAUDE_CONFIG_DIR/skills/swarm-cadence`, default `~/.claude`
- `SKILLS_DIR` directly overrides the final skills directory

- [x] **Step 4: Verify documentation and repository behavior**

Run:

```bash
rg -n 'macOS command-line tool|OpenClaw, ChatGPT, and Claude|SKILL_TARGET=codex|SKILL_TARGET=claude|CODEX_HOME|CLAUDE_CONFIG_DIR|SKILLS_DIR' README.md
git diff --check
make test
```

Expected: each documentation term is present, no whitespace errors are reported, and the Swift test suite passes.

- [x] **Step 5: Commit documentation**

```bash
git add README.md docs/superpowers/plans/2026-07-18-multi-agent-skill-install.md
git commit -m "Document multi-agent skill installation"
```
