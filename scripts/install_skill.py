#!/usr/bin/env python3
"""Install-time customization for the swarm-cadence OpenClaw skill."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ACCOUNT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")

CORE_COMMANDS_START = "## Core commands\n\n"
CORE_COMMANDS_END = "\nUse `swarm-cadence --help` for the current surface."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--dest", required=True, type=Path)
    parser.add_argument("--version-file", required=True, type=Path)
    parser.add_argument("--skill-name", required=True)
    parser.add_argument(
        "--accounts",
        required=True,
        help='Either exactly "single-account" or a whitespace-separated list of configured account labels.',
    )
    return parser.parse_args()


def normalize_accounts(raw: list[str]) -> tuple[str, list[str]]:
    if raw == ["single-account"]:
        return "single-account", []
    if "single-account" in raw:
        raise SystemExit('Use either "single-account" or account labels, not both.')

    seen: set[str] = set()
    accounts: list[str] = []
    for account in raw:
        if not ACCOUNT_RE.fullmatch(account):
            raise SystemExit(
                f"Invalid account label {account!r}. Use letters, numbers, _, ., or -, "
                "starting with a letter or number."
            )
        if account not in seen:
            seen.add(account)
            accounts.append(account)

    if not accounts:
        raise SystemExit('Missing account mode. Use "single-account" or account labels.')
    return "named-accounts", accounts


def command_lines_for_account(account: str | None) -> list[str]:
    account_flag = "" if account is None else f" --account {account}"
    return [
        f"swarm-cadence source status{account_flag} --format json",
        f"swarm-cadence auth status{account_flag} --format json",
        f"swarm-cadence db stats{account_flag} --format json",
        f"swarm-cadence ingest{account_flag} --adapter v2 --format json",
        f"swarm-cadence query categories{account_flag} --format json",
        f"swarm-cadence query venues{account_flag} --format json",
        f"swarm-cadence query visits{account_flag} --venue-id <venue-id> --format json",
        f"swarm-cadence query cadence{account_flag} --venue-id <venue-id> --from 2024-01-01 --format json",
        f"swarm-cadence query compare{account_flag} --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json",
        f"swarm-cadence evidence packet{account_flag} --date 2026-04-27 --baseline-from 2024-01-01 --recent-from 2026-01-01 --format json",
    ]


def build_core_commands(mode: str, accounts: list[str]) -> str:
    if mode == "single-account":
        return (
            "## Core commands\n\n"
            "This skill was installed for a single configured account. Do not pass `--account` in normal examples unless the human explicitly asks to override the account.\n\n"
            "```bash\n"
            + "\n".join(command_lines_for_account(None))
            + "\n```"
        )

    parts = [
        "## Core commands\n\n"
        "This skill was installed with explicit configured account labels. Pick the relevant account first; do not invent labels or use `default` unless the human explicitly says that is the configured label.\n"
        f"Configured accounts: {', '.join(f'`{account}`' for account in accounts)}.\n"
    ]
    for account in accounts:
        parts.append(f"\nFor account `{account}`:\n\n```bash\n")
        parts.append("\n".join(command_lines_for_account(account)))
        parts.append("\n```")
    return "".join(parts)


def replace_core_commands(text: str, replacement: str) -> str:
    start = text.index(CORE_COMMANDS_START)
    end = text.index(CORE_COMMANDS_END, start)
    return text[:start] + replacement + text[end:]


def rewrite_general_examples(text: str, mode: str, accounts: list[str]) -> str:
    first = accounts[0] if accounts else None
    if mode == "single-account":
        text = text.replace(
            "- Keep `--account` explicit (`default`, `partner`, or a configured label). Do not silently blend accounts.",
            "- This skill was installed in `single-account` mode. Omit `--account` by default; only pass it if the human explicitly asks to override the configured account.",
        )
        text = text.replace(
            "- When account scope is unclear or multiple people are possible, run `swarm-cadence source status --format json` first, then use an explicit `--account`.",
            "- When account scope is unclear, run `swarm-cadence source status --format json` first. If multiple accounts appear, ask which account to use rather than guessing.",
        )
        text = re.sub(r"\s--account\s+default\b", "", text)
        text = re.sub(r"\s--account\s+<account>\b", "", text)
    else:
        text = text.replace(
            "- Keep `--account` explicit (`default`, `partner`, or a configured label). Do not silently blend accounts.",
            f"- Keep `--account` explicit with one of the installed account labels: {', '.join(f'`{account}`' for account in accounts)}. Do not silently blend accounts.",
        )
        text = text.replace(
            "- When account scope is unclear or multiple people are possible, run `swarm-cadence source status --format json` first, then use an explicit `--account`.",
            f"- When account scope is unclear, ask which installed account to use ({', '.join(f'`{account}`' for account in accounts)}) or run source status for the candidate account before interpreting.",
        )
        text = text.replace("--account default", f"--account {first}")
        text = text.replace("--account <account>", f"--account {first}")
    return text


def add_install_state(dest: Path, source_root: Path, skill_name: str, version: str, mode: str, accounts: list[str]) -> None:
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source_root, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=source_root, text=True).strip())
    state = {
        "schema": "swarm-cadence.skill-install.v1",
        "skill": skill_name,
        "sourceRepo": str(source_root),
        "sourceCommit": commit,
        "sourceDirtyAtInstall": dirty,
        "repoVersion": version,
        "accountMode": mode,
        "accounts": accounts,
    }
    (dest / ".openclaw-skill-install.json").write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--validate-accounts":
        normalize_accounts(sys.argv[2].split())
        return 0

    args = parse_args()
    mode, accounts = normalize_accounts(args.accounts.split())

    version = args.version_file.read_text().strip()
    if not version:
        raise SystemExit(f"Empty version file: {args.version_file}")

    skill = args.dest / "SKILL.md"
    text = skill.read_text()
    text = replace_core_commands(text, build_core_commands(mode, accounts))
    text = rewrite_general_examples(text, mode, accounts)
    text = re.sub(r"\n<!-- repo-version: .*? -->\n?", "\n", text)
    text = text.rstrip() + f"\n\n<!-- repo-version: {version} -->\n"
    skill.write_text(text)

    add_install_state(args.dest, args.source_root, args.skill_name, version, mode, accounts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
