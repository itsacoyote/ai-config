#!/usr/bin/env python3
"""Validate the canonical harness-neutral isolated-role manifest."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

TOP_FIELDS = {"version", "contracts", "roles"}
ROLE_FIELDS = {"name", "description", "prompt", "skills", "mode", "tools"}
MODES = {"read-only", "verification", "implementation"}
TOOLS = {
    "read", "search", "shell", "web", "browser", "source-write",
    "test-artifact-write", "evidence-artifact-write", "commit",
}
WRITE_TOOLS = {"source-write", "test-artifact-write", "evidence-artifact-write"}
FORBIDDEN_PROMPT_PATTERNS = {
    "provider model alias": re.compile(r"\b(?:opus|sonnet|haiku)\b", re.I),
    "Claude-only path": re.compile(r"\.claude/"),
    "Claude tool syntax": re.compile(r"\b(?:AskUserQuestion|Agent tool|Skill\(|Task\()"),
    "provider tool syntax": re.compile(r"\bmcp__\w+"),
}
LINK_RE = re.compile(r"\[[^]]+\]\(([^)]+)\)")


def _is_string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and item for item in value)


def validate(root: Path, manifest_path: Path | None = None) -> list[str]:
    root = root.resolve()
    agents_dir = root / ".agents" / "agents"
    manifest_path = manifest_path or agents_dir / "roles.json"
    errors: list[str] = []

    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return [f"cannot read role manifest: {exc}"]

    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    unknown_top = set(manifest) - TOP_FIELDS
    missing_top = TOP_FIELDS - set(manifest)
    if unknown_top:
        errors.append(f"manifest unknown fields: {sorted(unknown_top)}")
    if missing_top:
        errors.append(f"manifest missing fields: {sorted(missing_top)}")
    if manifest.get("version") != 1:
        errors.append("manifest version must be 1")

    contracts = manifest.get("contracts")
    if contracts != {"qa_result": "qa-result.schema.json"}:
        errors.append("contracts must declare qa_result as qa-result.schema.json")
    else:
        qa_schema = agents_dir / contracts["qa_result"]
        if not qa_schema.is_file():
            errors.append(f"missing contract: {qa_schema}")

    roles = manifest.get("roles")
    if not isinstance(roles, list):
        errors.append("roles must be an array")
        return errors

    names: set[str] = set()
    source_editors: list[str] = []
    implementation_roles: list[str] = []
    verification_roles: list[str] = []

    for index, role in enumerate(roles):
        label = f"role[{index}]"
        if not isinstance(role, dict):
            errors.append(f"{label} must be an object")
            continue
        name = role.get("name") if isinstance(role.get("name"), str) else label
        unknown = set(role) - ROLE_FIELDS
        missing = ROLE_FIELDS - set(role)
        if unknown:
            errors.append(f"{name} unknown fields: {sorted(unknown)}")
        if missing:
            errors.append(f"{name} missing fields: {sorted(missing)}")
        if not isinstance(role.get("name"), str) or not re.fullmatch(r"[a-z0-9-]+", role["name"]):
            errors.append(f"{label} has invalid name")
        elif role["name"] in names:
            errors.append(f"duplicate role name: {role['name']}")
        else:
            names.add(role["name"])
        if not isinstance(role.get("description"), str) or not role["description"].strip():
            errors.append(f"{name} description must be a non-empty string")

        mode = role.get("mode")
        if mode not in MODES:
            errors.append(f"{name} invalid mode: {mode!r}")
        elif mode == "implementation":
            implementation_roles.append(name)
        elif mode == "verification":
            verification_roles.append(name)

        skills = role.get("skills")
        if not _is_string_list(skills) or len(skills) != len(set(skills or [])):
            errors.append(f"{name} skills must be a unique non-empty string array")
        else:
            for skill in skills:
                if not (root / ".agents" / "skills" / skill / "SKILL.md").is_file():
                    errors.append(f"{name} missing skill: {skill}")

        tools = role.get("tools")
        if not _is_string_list(tools) or len(tools) != len(set(tools or [])):
            errors.append(f"{name} tools must be a unique non-empty string array")
            tools = []
        else:
            invalid_tools = set(tools) - TOOLS
            if invalid_tools:
                errors.append(f"{name} invalid tools: {sorted(invalid_tools)}")
        writes = set(tools) & WRITE_TOOLS
        if mode == "read-only" and writes:
            errors.append(f"{name} read-only role declares writes: {sorted(writes)}")
        if mode == "verification" and "source-write" in writes:
            errors.append(f"{name} verification role declares source-write")
        if "source-write" in tools:
            source_editors.append(name)

        prompt_name = role.get("prompt")
        if not isinstance(prompt_name, str) or Path(prompt_name).name != prompt_name:
            errors.append(f"{name} prompt must be a local filename")
            continue
        if prompt_name != f"{name}.md":
            errors.append(f"{name} prompt must be {name}.md")
        prompt_path = agents_dir / prompt_name
        if not prompt_path.is_file():
            errors.append(f"{name} missing prompt: {prompt_name}")
            continue
        prompt = prompt_path.read_text()
        for reason, pattern in FORBIDDEN_PROMPT_PATTERNS.items():
            if pattern.search(prompt):
                errors.append(f"{name} contains {reason}")
        for target in LINK_RE.findall(prompt):
            if "://" in target or target.startswith(("#", "mailto:")):
                continue
            local = target.split("#", 1)[0]
            if local and not (prompt_path.parent / local).resolve().exists():
                errors.append(f"{name} missing prompt reference: {target}")

    if source_editors != ["implementer"]:
        errors.append(f"implementer must be the only source editor: {source_editors}")
    if implementation_roles != ["implementer"]:
        errors.append(f"implementer must be the only implementation role: {implementation_roles}")
    if verification_roles != ["qa-review"]:
        errors.append(f"qa-review must be the only verification role: {verification_roles}")
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    errors = validate(root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    manifest = json.loads((root / ".agents" / "agents" / "roles.json").read_text())
    print(f"validated {len(manifest['roles'])} neutral roles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
