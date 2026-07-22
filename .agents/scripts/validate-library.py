#!/usr/bin/env python3
"""Validate the complete portable agent library and its ownership manifest."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import tempfile
import tomllib
from pathlib import Path

SELF = ".agents/manifest.json"
TOP_KEYS = {"version", "library", "ownership", "explicit_only", "portability", "roles", "source_parity"}
PORTABILITY_CLASSES = {"portable", "adapted", "harness-orchestrated", "capability-limited"}
LINK = re.compile(r"\[[^]]+\]\(([^)]+)\)")
FORBIDDEN = ("${CLAUDE_SKILL_DIR}", ".claude/", "Agent(", "Agent tool")


class InvalidLibrary(ValueError):
    pass


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def regular_file(root: Path, path: Path) -> None:
    relative = path.relative_to(root)
    current = root
    for part in relative.parts:
        current = current / part
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise InvalidLibrary(f"symlink payload/path component is forbidden: {relative}")
    if not stat.S_ISREG(path.lstat().st_mode):
        raise InvalidLibrary(f"non-regular payload is forbidden: {relative}")
    if not path.resolve().is_relative_to(root.resolve()):
        raise InvalidLibrary(f"payload escapes library root: {relative}")


def safe_directory(root: Path, path: Path) -> None:
    relative = path.relative_to(root)
    current = root
    for part in relative.parts:
        current = current / part
        metadata = current.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise InvalidLibrary(f"symlink directory/path component is forbidden: {relative}")
    if not stat.S_ISDIR(path.lstat().st_mode) or not path.resolve().is_relative_to(root.resolve()):
        raise InvalidLibrary(f"unsafe directory: {relative}")


def payload_files(root: Path) -> set[str]:
    files: set[str] = set()
    candidates = [root / "AGENTS.md"]
    for directory in (root / ".agents", root / ".codex"):
        if directory.is_dir():
            for parent, directories, filenames in os.walk(directory, followlinks=False):
                base = Path(parent)
                for name in directories:
                    candidate = base / name
                    if candidate.is_symlink():
                        raise InvalidLibrary(f"symlink directory is forbidden: {candidate.relative_to(root)}")
                candidates.extend(base / name for name in filenames)
    for path in candidates:
        if not path.exists() and not path.is_symlink():
            continue
        if "__pycache__" in path.parts or path.name.endswith(".pyc"):
            continue
        regular_file(root, path)
        files.add(str(path.relative_to(root)))
    return files


def safe_relative(root: Path, relative: str, *, prefix: str | None = None) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative:
        raise InvalidLibrary(f"unsafe manifest path: {relative!r}")
    path = Path(relative)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts) or path.as_posix() != relative:
        raise InvalidLibrary(f"unsafe manifest path: {relative!r}")
    if prefix and not relative.startswith(prefix):
        raise InvalidLibrary(f"manifest path is outside {prefix}: {relative}")
    resolved = root / path
    if not resolved.resolve().is_relative_to(root.resolve()):
        raise InvalidLibrary(f"manifest path escapes root: {relative}")
    return resolved


def load_manifest(root: Path) -> dict:
    try:
        manifest = json.loads((root / SELF).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidLibrary(f"manifest unreadable: {error}") from error
    if not isinstance(manifest, dict) or set(manifest) != TOP_KEYS:
        raise InvalidLibrary("manifest schema has unknown or missing top-level fields")
    if manifest.get("version") != 1:
        raise InvalidLibrary(f"unsupported manifest version: {manifest.get('version')!r}")
    ownership = manifest.get("ownership")
    if not isinstance(ownership, dict) or set(ownership) != {"self", "checksum_algorithm", "files", "checksums"}:
        raise InvalidLibrary("invalid ownership schema")
    if ownership["self"] != SELF or ownership["checksum_algorithm"] != "sha256":
        raise InvalidLibrary("invalid manifest self/checksum contract")
    if not isinstance(ownership["files"], list) or not all(isinstance(value, str) for value in ownership["files"]):
        raise InvalidLibrary("ownership files have invalid types")
    if not isinstance(ownership["checksums"], dict) or not all(isinstance(key, str) and isinstance(value, str) for key, value in ownership["checksums"].items()):
        raise InvalidLibrary("ownership checksums have invalid types")
    library = manifest["library"]
    if not isinstance(library, dict) or set(library) != {"skill_count", "role_count"} or not all(type(value) is int and value >= 0 for value in library.values()):
        raise InvalidLibrary("invalid library schema")
    explicit = manifest["explicit_only"]
    if not isinstance(explicit, dict) or set(explicit) != {"skills", "policy_path"}:
        raise InvalidLibrary("invalid explicit-only schema")
    portability = manifest["portability"]
    if not isinstance(portability, dict) or set(portability) != {"exceptions", "skills"} or not isinstance(portability["exceptions"], dict) or not isinstance(portability["skills"], dict):
        raise InvalidLibrary("invalid portability schema")
    roles = manifest["roles"]
    if not isinstance(roles, dict) or set(roles) != {"names", "codex_adapters"} or not isinstance(roles["names"], list) or not isinstance(roles["codex_adapters"], dict):
        raise InvalidLibrary("invalid roles schema")
    parity = manifest["source_parity"]
    parity_keys = {"source_root", "portable_only", "adapted_primary", "adapted_support", "omitted", "portable_additions", "source_checksums"}
    if not isinstance(parity, dict) or set(parity) != parity_keys or not isinstance(parity["source_checksums"], dict):
        raise InvalidLibrary("invalid source parity schema")
    for key in ("portable_only", "adapted_primary", "adapted_support", "omitted", "portable_additions"):
        values = parity[key]
        if not isinstance(values, list) or values != sorted(set(values)) or not all(isinstance(value, str) for value in values):
            raise InvalidLibrary(f"source parity {key} must be a unique sorted string list")
    return manifest


def validate_ownership(root: Path, manifest: dict) -> None:
    ownership = manifest["ownership"]
    owned = ownership["files"]
    if owned != sorted(set(owned)):
        raise InvalidLibrary("owned files must be unique and sorted")
    for relative in owned:
        safe_relative(root, relative)
    actual = payload_files(root)
    if set(owned) != actual:
        missing = sorted(actual - set(owned)); extra = sorted(set(owned) - actual)
        raise InvalidLibrary(f"manifest ownership mismatch; missing={missing}, extra={extra}")
    checksums = ownership["checksums"]
    if set(checksums) != actual - {SELF} or SELF in checksums:
        raise InvalidLibrary("manifest must checksum every payload except itself")
    for relative, expected in checksums.items():
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", expected) or digest(root / relative) != expected:
            raise InvalidLibrary(f"checksum mismatch: {relative}")


def frontmatter(path: Path) -> tuple[str, str, str]:
    text = path.read_text()
    if not text.startswith("---\n") or text.count("---\n") < 2:
        raise InvalidLibrary(f"invalid skill frontmatter: {path}")
    header = text.split("---\n", 2)[1]
    def one(pattern: str, label: str) -> str:
        values = re.findall(pattern, header, re.MULTILINE)
        if len(values) != 1 or not isinstance(values[0], str) or not values[0].strip():
            raise InvalidLibrary(f"invalid skill {label}: {path}")
        return values[0].strip()
    name = one(r"^name: ([^\n]+)$", "name")
    description = one(r"^description: ([^\n]+)$", "description")
    blocks = re.findall(r"^metadata:\s*\n((?:  [^\n]*\n?)*)", header, re.MULTILINE)
    if len(blocks) != 1:
        raise InvalidLibrary(f"invalid skill metadata: {path}")
    categories = re.findall(r"^  category: ([a-z][a-z0-9-]*)$", blocks[0], re.MULTILINE)
    if len(categories) != 1:
        raise InvalidLibrary(f"invalid skill metadata.category: {path}")
    return name, description, categories[0]


def validate_skills(root: Path, manifest: dict) -> list[str]:
    skills_root = root / ".agents/skills"
    nested = [path for path in skills_root.rglob("SKILL.md") if path.parent.parent != skills_root]
    if nested:
        raise InvalidLibrary(f"nested skill layout is forbidden: {nested[0]}")
    names: list[str] = []
    categories: dict[str, str] = {}
    for path in sorted(skills_root.glob("*/SKILL.md")):
        name, _, category = frontmatter(path)
        if name != path.parent.name:
            raise InvalidLibrary(f"skill name/directory mismatch: {path}")
        names.append(name); categories[name] = category
    if len(names) != len(set(names)):
        raise InvalidLibrary("skill name collision")
    expected = manifest["library"]
    if set(expected) != {"skill_count", "role_count"} or len(names) != expected["skill_count"]:
        raise InvalidLibrary("skill inventory count mismatch")
    classes = manifest["portability"]["skills"]
    if set(classes) != set(names) or any(value not in PORTABILITY_CLASSES for value in classes.values()):
        raise InvalidLibrary("portability matrix does not cover every skill")
    return names


def validate_links(root: Path) -> None:
    sources = list((root / ".agents/skills").rglob("*.md"))
    sources += list((root / ".agents/agents").glob("*.md"))
    sources += list((root / ".agents/references").glob("*.md"))
    sources += [root / ".agents/compatibility.md", root / ".agents/catalog.md"]
    for source in sources:
        for target in LINK.findall(source.read_text()):
            clean = target.split("#", 1)[0]
            if not clean or clean.startswith(("http://", "https://", "mailto:", "/")):
                continue
            if not (source.parent / clean).resolve().exists():
                raise InvalidLibrary(f"dead link in {source.relative_to(root)}: {target}")


def validate_portability(root: Path, manifest: dict) -> None:
    exceptions = manifest["portability"]["exceptions"]
    sources = []
    for path in (root / ".agents/skills").rglob("*"):
        if not path.is_file(): continue
        try:
            path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            continue
        sources.append(path)
    sources += list((root / ".agents/agents").glob("*.md")) + list((root / ".agents/references").glob("*.md"))
    seen_exceptions: set[str] = set()
    for source in sources:
        relative = str(source.relative_to(root)); text = source.read_text(encoding="utf-8", errors="strict")
        found = [token for token in FORBIDDEN if token in text]
        allowed = exceptions.get(relative, [])
        if not isinstance(allowed, list) or allowed != sorted(set(allowed)) or any(token not in FORBIDDEN for token in allowed):
            raise InvalidLibrary(f"invalid portability exception: {relative}")
        unapproved = sorted(set(found) - set(allowed))
        if unapproved:
            raise InvalidLibrary(f"portable content contains unapproved harness syntax in {relative}: {unapproved}")
        if allowed:
            seen_exceptions.add(relative)
            if set(found) != set(allowed):
                raise InvalidLibrary(f"stale portability exception: {relative}")
    if seen_exceptions != set(exceptions):
        raise InvalidLibrary("portability exceptions reference missing or non-text payloads")


def validate_explicit(root: Path, manifest: dict, skill_names: list[str]) -> None:
    policy = manifest["explicit_only"]
    if set(policy) != {"skills", "policy_path"} or policy["policy_path"] != "agents/openai.yaml":
        raise InvalidLibrary("invalid explicit-only policy schema")
    declared = policy["skills"]
    if declared != sorted(set(declared)) or not set(declared) <= set(skill_names):
        raise InvalidLibrary("invalid explicit-only skill inventory")
    actual = sorted(path.parents[1].name for path in (root / ".agents/skills").glob("*/agents/openai.yaml"))
    if actual != declared:
        raise InvalidLibrary("explicit invocation policy coverage mismatch")
    for name in declared:
        text = (root / f".agents/skills/{name}/agents/openai.yaml").read_text()
        if not re.fullmatch(r"policy:\n  allow_implicit_invocation: false\n?", text):
            raise InvalidLibrary(f"explicit invocation policy must use the exact false-only schema: {name}")


def validate_roles(root: Path, manifest: dict) -> list[str]:
    trusted_validator = Path(__file__).resolve().parent / "validate-roles.py"
    spec = importlib.util.spec_from_file_location("trusted_validate_roles", trusted_validator)
    if spec is None or spec.loader is None:
        raise InvalidLibrary("trusted neutral role validator is unavailable")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    errors = module.validate(root)
    if errors:
        raise InvalidLibrary(f"neutral role contract invalid: {'; '.join(errors)}")
    roles_data = json.loads((root / ".agents/agents/roles.json").read_text())
    roles = roles_data.get("roles", [])
    names = [role.get("name") for role in roles]
    declared = manifest["roles"]
    if set(declared) != {"names", "codex_adapters"} or declared["names"] != names:
        raise InvalidLibrary("role manifest coverage mismatch")
    if len(names) != manifest["library"]["role_count"] or set(declared["codex_adapters"]) != set(names):
        raise InvalidLibrary("role adapter coverage mismatch")
    mapped = list(declared["codex_adapters"].values())
    owned = set(manifest["ownership"]["files"])
    for relative in mapped:
        safe_relative(root, relative, prefix=".codex/agents/")
        if relative not in owned:
            raise InvalidLibrary(f"role adapter is not owned: {relative}")
    physical = {str(path.relative_to(root)) for path in (root / ".codex/agents").glob("*.toml")}
    if len(mapped) != len(set(mapped)) or set(mapped) != physical:
        raise InvalidLibrary("role adapter physical inventory mismatch")
    for role in roles:
        name = role["name"]
        relative = declared["codex_adapters"][name]
        adapter_path = safe_relative(root, relative, prefix=".codex/agents/")
        regular_file(root, adapter_path)
        adapter = tomllib.loads(adapter_path.read_text())
        if adapter.get("name") != name:
            raise InvalidLibrary(f"role adapter name mismatch: {name}")
        mode = role["mode"]
        sandbox = adapter.get("sandbox_mode")
        expected = "read-only" if mode == "read-only" else "workspace-write" if mode == "verification" else None
        if sandbox != expected:
            raise InvalidLibrary(f"role adapter sandbox mismatch: {name}")
    return names


def validate_source_parity(root: Path, manifest: dict) -> None:
    policy = manifest["source_parity"]
    if policy["source_root"] != ".claude/skills":
        raise InvalidLibrary("invalid source parity root")
    source = safe_relative(root, policy["source_root"]); target = root / ".agents/skills"
    safe_directory(root, source)
    adapted_primary = set(policy["adapted_primary"]); adapted_support = set(policy["adapted_support"])
    omitted = set(policy["omitted"]); adapted = adapted_primary | adapted_support
    if adapted_primary & adapted_support or adapted & omitted:
        raise InvalidLibrary("source parity classifications overlap")
    source_files: dict[str, Path] = {}
    for parent, directories, filenames in os.walk(source, followlinks=False):
        base = Path(parent)
        for name in directories:
            safe_directory(root, base / name)
        for name in filenames:
            path = base / name; regular_file(root, path)
            source_files[str(path.relative_to(source))] = path
    if set(policy["source_checksums"]) != set(source_files):
        raise InvalidLibrary("source checksum inventory is incomplete")
    for relative, path in source_files.items():
        expected = policy["source_checksums"][relative]
        if not isinstance(expected, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", expected) or digest(path) != expected:
            raise InvalidLibrary(f"source checksum drift: {relative}")
        portable = target / relative
        if relative in omitted:
            if portable.exists(): raise InvalidLibrary(f"omitted source unexpectedly exists: {relative}")
            continue
        if not portable.is_file(): raise InvalidLibrary(f"source parity missing payload: {relative}")
        if relative not in adapted and path.read_bytes() != portable.read_bytes():
            raise InvalidLibrary(f"source parity drift: {relative}")
    if not adapted <= set(source_files) or not omitted <= set(source_files):
        raise InvalidLibrary("source parity classification references a missing source")
    if any(not value.endswith("/SKILL.md") for value in adapted_primary):
        raise InvalidLibrary("adapted primary inventory contains a non-primary file")
    additions = {str(path.relative_to(target)) for path in target.rglob("*") if path.is_file() and not (source / path.relative_to(target)).exists()}
    if additions != set(policy["portable_additions"]):
        raise InvalidLibrary("source parity portable additions mismatch")
    portable_only = {path.parts[0] for value in policy["portable_only"] for path in [Path(value)]}
    if portable_only != {Path(value).parts[0] for value in additions if Path(value).parts[0] not in {Path(item).parts[0] for item in policy["adapted_primary"]}}:
        raise InvalidLibrary("portable-only skill inventory mismatch")


def validate_catalog(root: Path) -> None:
    grouped: dict[str, list[tuple[str, str]]] = {}
    for path in sorted((root / ".agents/skills").glob("*/SKILL.md")):
        name, description, category = frontmatter(path)
        grouped.setdefault(category, []).append((name, description))
    def title(category: str) -> str:
        return " ".join(part.upper() if part in {"qa", "api"} else part.capitalize() for part in category.split("-"))
    lines = ["# Agent Skills Catalog", "", "Generated by `.agents/scripts/generate-catalog.py`. Do not edit by hand.", ""]
    for category in sorted(grouped, key=lambda value: title(value).casefold()):
        lines.extend((f"## {title(category)}", ""))
        for name, description in sorted(grouped[category]):
            lines.append(f"- [`{name}`](skills/{name}/SKILL.md) — {description}")
        lines.append("")
    expected = "\n".join(lines)
    if (root / ".agents/catalog.md").read_text() != expected:
        raise InvalidLibrary("catalog validation failed: stale catalog")


def validate_compatibility(root: Path, manifest: dict, skills: list[str], roles: list[str]) -> None:
    text = (root / ".agents/compatibility.md").read_text()
    try:
        skill_section, role_section = text.split("## Skills", 1)[1].split("## Isolated roles", 1)
    except ValueError as error:
        raise InvalidLibrary("compatibility matrix sections are missing") from error
    def rows(section: str, width: int) -> set[tuple[str, ...]]:
        result: list[tuple[str, ...]] = []
        for line in section.splitlines():
            if not line.startswith("| `"): continue
            cells = tuple(cell.strip().strip("`") for cell in line.strip("|").split("|"))
            if len(cells) != width: raise InvalidLibrary("compatibility matrix row has invalid width")
            result.append(cells)
        if len(result) != len(set(result)):
            raise InvalidLibrary("compatibility matrix contains duplicate rows")
        return set(result)
    labels = {"portable": "Portable", "adapted": "Adapted paths/frontmatter", "harness-orchestrated": "Harness orchestration", "capability-limited": "Capability-limited"}
    expected_skills = set()
    for name in skills:
        _, _, category = frontmatter(root / f".agents/skills/{name}/SKILL.md")
        expected_skills.add((name, category, labels[manifest["portability"]["skills"][name]]))
    if rows(skill_section, 3) != expected_skills:
        raise InvalidLibrary("compatibility skill matrix values mismatch")
    role_data = {role["name"]: role for role in json.loads((root / ".agents/agents/roles.json").read_text())["roles"]}
    expected_roles = {
        (name, role_data[name]["mode"], manifest["roles"]["codex_adapters"][name],
         "supervised sandbox launcher" if role_data[name]["mode"] == "implementation" else "generic isolated runner")
        for name in roles
    }
    if rows(role_section, 4) != expected_roles:
        raise InvalidLibrary("compatibility role matrix values mismatch")


def validate_semantics(root: Path, manifest: dict) -> tuple[int, int]:
    skills = validate_skills(root, manifest)
    validate_links(root)
    validate_portability(root, manifest)
    validate_explicit(root, manifest, skills)
    roles = validate_roles(root, manifest)
    validate_source_parity(root, manifest)
    validate_catalog(root)
    validate_compatibility(root, manifest, skills, roles)
    return len(skills), len(roles)


def refresh_manifest(root: Path, *, accept_inventory_changes: bool) -> None:
    manifest = load_manifest(root)
    files = sorted(payload_files(root) | {SELF})
    previous = set(manifest["ownership"]["files"]); current = set(files)
    if previous != current and not accept_inventory_changes:
        raise InvalidLibrary(f"inventory changed; rerun with --accept-inventory-changes after review; added={sorted(current-previous)}, removed={sorted(previous-current)}")
    manifest["ownership"]["files"] = files
    manifest["ownership"]["checksums"] = {relative: digest(root / relative) for relative in files if relative != SELF}
    validate_semantics(root, manifest)
    target = root / SELF
    descriptor, temporary_name = tempfile.mkstemp(prefix=".manifest-", suffix=".tmp", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "w") as stream:
            descriptor = -1
            stream.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if descriptor >= 0: os.close(descriptor)
        temporary.unlink(missing_ok=True)


def validate(root: Path) -> tuple[int, int]:
    manifest = load_manifest(root)
    validate_ownership(root, manifest)
    return validate_semantics(root, manifest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--refresh-manifest", action="store_true")
    parser.add_argument("--accept-inventory-changes", action="store_true")
    args = parser.parse_args(); root = args.root.resolve()
    if args.accept_inventory_changes and not args.refresh_manifest:
        parser.error("--accept-inventory-changes requires --refresh-manifest")
    try:
        if args.refresh_manifest:
            refresh_manifest(root, accept_inventory_changes=args.accept_inventory_changes)
            print("refreshed manifest ownership and checksums"); return 0
        skills, roles = validate(root)
    except (InvalidLibrary, OSError, KeyError, TypeError, ValueError, json.JSONDecodeError, tomllib.TOMLDecodeError) as error:
        print(f"validate-library: {error}", file=sys.stderr); return 1
    print(f"validated {skills} skills and {roles} roles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
