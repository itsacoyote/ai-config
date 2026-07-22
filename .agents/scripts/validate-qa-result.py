#!/usr/bin/env python3
"""Validate portable QA result envelopes and determine their next action."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED_FIELDS = {
    "schema_version",
    "verdict",
    "attempt",
    "summary",
    "evidence",
    "failing_command",
    "affected_paths",
    "implementer_instructions",
    "blocker",
}
VERDICTS = {"APPROVED", "FIX_REQUIRED", "BLOCKED"}
LEGACY_VERDICTS = {
    "Approved": "APPROVED",
    "Gaps": "FIX_REQUIRED",
    "Blocked": "BLOCKED",
}


def _nonempty_string(value: Any, field: str, *, nullable: bool = False) -> None:
    if nullable and value is None:
        return
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string")


def _string_list(value: Any, field: str, *, nonempty: bool = False) -> None:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise ValueError(f"{field} must be an array of non-empty strings")
    if nonempty and not value:
        raise ValueError(f"{field} must contain at least one item")


def validate_result(result: Any) -> None:
    if not isinstance(result, dict):
        raise ValueError("result must be a JSON object")

    fields = set(result)
    missing = REQUIRED_FIELDS - fields
    unknown = fields - REQUIRED_FIELDS
    if missing:
        raise ValueError(f"missing required fields: {', '.join(sorted(missing))}")
    if unknown:
        raise ValueError(f"unknown fields: {', '.join(sorted(unknown))}")

    if result["schema_version"] != 1:
        raise ValueError("schema_version must be 1")
    if result["verdict"] not in VERDICTS:
        raise ValueError("verdict must be APPROVED, FIX_REQUIRED, or BLOCKED")
    if type(result["attempt"]) is not int or not 1 <= result["attempt"] <= 3:
        raise ValueError("attempt must be an integer from 1 through 3")

    _nonempty_string(result["summary"], "summary")
    _string_list(result["evidence"], "evidence")
    _string_list(result["affected_paths"], "affected_paths")

    verdict = result["verdict"]
    if verdict == "APPROVED":
        if result["failing_command"] is not None:
            raise ValueError("failing_command must be null for APPROVED")
        if result["affected_paths"]:
            raise ValueError("affected_paths must be empty for APPROVED")
        if result["implementer_instructions"] is not None:
            raise ValueError("implementer_instructions must be null for APPROVED")
        if result["blocker"] is not None:
            raise ValueError("blocker must be null for APPROVED")
    elif verdict == "FIX_REQUIRED":
        _nonempty_string(result["failing_command"], "failing_command")
        _string_list(result["evidence"], "evidence", nonempty=True)
        _string_list(result["affected_paths"], "affected_paths", nonempty=True)
        _nonempty_string(result["implementer_instructions"], "implementer_instructions")
        if result["blocker"] is not None:
            raise ValueError("blocker must be null for FIX_REQUIRED")
    else:
        _nonempty_string(result["blocker"], "blocker")
        if result["implementer_instructions"] is not None:
            raise ValueError("implementer_instructions must be null for BLOCKED")


def next_action(result: Any) -> str:
    validate_result(result)
    if result["verdict"] == "APPROVED":
        return "PASS"
    if result["verdict"] == "FIX_REQUIRED" and result["attempt"] < 3:
        return "DISPATCH_IMPLEMENTER"
    return "BLOCK"


def safe_next_action(result: Any) -> str:
    try:
        return next_action(result)
    except (TypeError, ValueError):
        return "BLOCK"


def map_legacy_verdict(verdict: str) -> str:
    try:
        return LEGACY_VERDICTS[verdict]
    except KeyError as error:
        raise ValueError(f"unknown legacy verdict: {verdict}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result", type=Path, help="Path to a QA result JSON file")
    parser.add_argument("--action", action="store_true", help="Print PASS, DISPATCH_IMPLEMENTER, or BLOCK")
    args = parser.parse_args()

    try:
        result = json.loads(args.result.read_text())
        validate_result(result)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid QA result: {error}", file=sys.stderr)
        return 1

    print(next_action(result) if args.action else "valid QA result")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
