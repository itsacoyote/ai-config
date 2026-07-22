#!/usr/bin/env python3
"""Executable no-op Codex adapter used only for workflow contract smoke tests."""

from __future__ import annotations

import argparse
import tomllib
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--status", default="DONE")
    args = parser.parse_args()
    adapter = tomllib.loads(args.adapter.read_text())
    config = tomllib.loads(args.config.read_text())
    if adapter.get("name") != "implementer":
        parser.error("adapter is not implementer")
    if "canonical neutral role `implementer`" not in adapter.get("developer_instructions", ""):
        parser.error("adapter does not consume the neutral implementer role")
    if config.get("agents", {}).get("max_depth") != 1:
        parser.error("Codex nesting depth is not bounded")
    if not args.task.strip():
        parser.error("task is empty")
    print(f"STATUS: {args.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
