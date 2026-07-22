#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TARGET=${HOME}/.agents
DRY_RUN=0
REPLACE=0

usage() {
  cat <<'EOF'
Usage: install-library.sh [--source AGENTS_DIR] [--target AGENTS_DIR] [--dry-run] [--replace]

Installs the complete portable .agents tree. Codex project adapters are intentionally
not installed. --replace permits replacement of reported collisions and modified
owned files. Prior-only files are removed only when the source manifest authenticates
the exact prior manifest through installation.upgrade_from_manifest_sha256.
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; SOURCE=$2; shift 2 ;;
    --target) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; TARGET=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --replace) REPLACE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install-library: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$SOURCE" "$TARGET" "$DRY_RUN" "$REPLACE" <<'PY'
from __future__ import annotations
import errno, hashlib, json, os, secrets, stat, sys
from pathlib import Path

source_path = Path(sys.argv[1]).expanduser().absolute()
target_path = Path(sys.argv[2]).expanduser().absolute()
dry_run = sys.argv[3] == "1"
replace = sys.argv[4] == "1"
SELF = ".agents/manifest.json"
DIR_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
FILE_FLAGS = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)

class InstallError(Exception): pass

def checksum(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()

def safe_suffix(value: str) -> str:
    if not isinstance(value, str) or not value.startswith(".agents/") or "\\" in value:
        raise InstallError(f"unsafe manifest path: {value!r}")
    path = Path(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts) or path.as_posix() != value:
        raise InstallError(f"unsafe manifest path: {value!r}")
    return value[len(".agents/"):]

def open_absolute_directory(path: Path, *, create: bool, missing_ok: bool = False) -> int | None:
    if not path.is_absolute(): raise InstallError(f"directory path must be absolute: {path}")
    descriptor = os.open(path.anchor, DIR_FLAGS)
    try:
        for part in path.parts[1:]:
            try:
                child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if missing_ok and not create:
                    os.close(descriptor); return None
                if not create: raise InstallError(f"directory does not exist: {path}")
                try: os.mkdir(part, 0o755, dir_fd=descriptor)
                except FileExistsError: pass
                child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            except OSError as error:
                raise InstallError(f"unsafe or non-directory path component in {path}: {part}: {error}") from error
            os.close(descriptor); descriptor = child
        return descriptor
    except Exception:
        try: os.close(descriptor)
        except OSError: pass
        raise

def open_parent(root_fd: int, suffix: str, *, create: bool, cache: dict[tuple[str, ...], int] | None = None) -> tuple[int, str]:
    parts = Path(suffix).parts
    if not parts or any(part in {"", ".", ".."} for part in parts): raise InstallError(f"unsafe relative path: {suffix}")
    prefix: tuple[str, ...] = ()
    descriptor = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            prefix += (part,)
            if cache is not None and prefix in cache:
                child = os.dup(cache[prefix])
            else:
                try: child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
                except FileNotFoundError:
                    if not create: raise
                    try: os.mkdir(part, 0o755, dir_fd=descriptor)
                    except FileExistsError: pass
                    child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
                except OSError as error:
                    raise InstallError(f"unsafe destination parent for {suffix}: {error}") from error
                if cache is not None: cache[prefix] = os.dup(child)
            os.close(descriptor); descriptor = child
        return descriptor, parts[-1]
    except Exception:
        os.close(descriptor); raise

def read_leaf(parent_fd: int, name: str, *, missing_ok: bool) -> tuple[bytes, int] | None:
    try: descriptor = os.open(name, FILE_FLAGS, dir_fd=parent_fd)
    except FileNotFoundError:
        if missing_ok: return None
        raise
    except OSError as error:
        raise InstallError(f"cannot safely open payload {name}: {error}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode): raise InstallError(f"payload is not a regular file: {name}")
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk: break
            chunks.append(chunk)
        after = os.fstat(descriptor)
        identity = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        if identity != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise InstallError(f"payload changed while reading: {name}")
        return b"".join(chunks), stat.S_IMODE(before.st_mode)
    finally: os.close(descriptor)

def read_relative(root_fd: int | None, suffix: str) -> tuple[bytes, int] | None:
    if root_fd is None: return None
    try: parent, name = open_parent(root_fd, suffix, create=False)
    except FileNotFoundError: return None
    try: return read_leaf(parent, name, missing_ok=True)
    finally: os.close(parent)

def load_manifest(data: bytes, label: str) -> dict:
    try: value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as error: raise InstallError(f"{label} manifest is invalid: {error}") from error
    if not isinstance(value, dict): raise InstallError(f"{label} manifest root must be an object")
    if value.get("version") != 1: raise InstallError(f"{label} manifest has unsupported version")
    ownership = value.get("ownership")
    if not isinstance(ownership, dict) or ownership.get("self") != SELF or ownership.get("checksum_algorithm") != "sha256":
        raise InstallError(f"{label} manifest ownership schema is invalid")
    files, sums = ownership.get("files"), ownership.get("checksums")
    if not isinstance(files, list) or not all(isinstance(item, str) for item in files) or files != sorted(set(files)):
        raise InstallError(f"{label} manifest file inventory is invalid")
    if not isinstance(sums, dict) or not all(isinstance(key, str) and isinstance(item, str) for key, item in sums.items()):
        raise InstallError(f"{label} manifest checksum inventory is invalid")
    if SELF not in files or SELF in sums: raise InstallError(f"{label} manifest self-checksum contract is invalid")
    installation = value.get("installation")
    if not isinstance(installation, dict) or set(installation) != {"upgrade_from_manifest_sha256"}:
        raise InstallError(f"{label} manifest installation schema is invalid")
    trusted = installation["upgrade_from_manifest_sha256"]
    if not isinstance(trusted, list) or not all(isinstance(item, str) and len(item) == 71 and item.startswith("sha256:") for item in trusted) or trusted != sorted(set(trusted)):
        raise InstallError(f"{label} trusted prior manifest inventory is invalid")
    return value

def selected(manifest: dict) -> tuple[set[str], dict[str, str]]:
    ownership = manifest["ownership"]
    files = {item for item in ownership["files"] if item.startswith(".agents/")}
    sums = {key: item for key, item in ownership["checksums"].items() if key.startswith(".agents/")}
    if set(sums) != files - {SELF}: raise InstallError("manifest does not checksum every selected payload except itself")
    for relative in files: safe_suffix(relative)
    for value in sums.values():
        if len(value) != 71 or not value.startswith("sha256:"):
            raise InstallError("manifest contains an invalid checksum")
    return files, sums

def create_file_no_replace(parent_fd: int, name: str, data: bytes, mode: int) -> None:
    temporary = f".install-{secrets.token_hex(16)}"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    created = False
    try:
        file_fd = os.open(temporary, flags, 0o600, dir_fd=parent_fd); created = True
        try:
            view = memoryview(data)
            while view: view = view[os.write(file_fd, view):]
            os.fchmod(file_fd, mode); os.fsync(file_fd)
        finally: os.close(file_fd)
        try: os.link(temporary, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd, follow_symlinks=False)
        except FileExistsError as error: raise InstallError(f"destination appeared during installation: {name}") from error
    finally:
        if created:
            try: os.unlink(temporary, dir_fd=parent_fd)
            except FileNotFoundError: pass

def quarantine(parent_fd: int, name: str, expected: tuple[str, int] | None, relative: str) -> str | None:
    quarantine_name = f".install-backup-{secrets.token_hex(16)}"
    try: os.rename(name, quarantine_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
    except FileNotFoundError:
        if expected is None: return None
        raise InstallError(f"destination disappeared after preflight: {relative}")
    return quarantine_name

source_fd = target_fd = None
cache: dict[tuple[str, ...], int] = {}
try:
    source_fd = open_absolute_directory(source_path, create=False)
    assert source_fd is not None
    manifest_value = read_relative(source_fd, "manifest.json")
    if manifest_value is None: raise InstallError("source manifest is missing")
    source_manifest_bytes, manifest_mode = manifest_value
    source_manifest = load_manifest(source_manifest_bytes, "source")
    source_files, source_sums = selected(source_manifest)

    # Immutable authenticated snapshot: all later installs use these exact bytes.
    snapshot: dict[str, tuple[bytes, int]] = {}
    for relative, expected in sorted(source_sums.items()):
        value = read_relative(source_fd, safe_suffix(relative))
        if value is None: raise InstallError(f"source payload is missing: {relative}")
        if checksum(value[0]) != expected: raise InstallError(f"source checksum mismatch: {relative}")
        snapshot[relative] = value

    target_fd = open_absolute_directory(target_path, create=False, missing_ok=True)
    prior_value = read_relative(target_fd, "manifest.json")
    prior_manifest_bytes = prior_value[0] if prior_value else None
    prior_manifest = None
    if prior_manifest_bytes is not None:
        try: prior_manifest = load_manifest(prior_manifest_bytes, "prior target")
        except InstallError:
            if not replace: raise
    if prior_manifest is not None and prior_manifest_bytes != source_manifest_bytes:
        if checksum(prior_manifest_bytes) not in source_manifest["installation"]["upgrade_from_manifest_sha256"]:
            if not replace: raise InstallError("prior target manifest is not authenticated by the source upgrade policy")
            prior_manifest = None
    prior_files, prior_sums = selected(prior_manifest) if prior_manifest else (set(), {})

    copies: list[tuple[str, tuple[str, int] | None]] = []
    removals: list[tuple[str, tuple[str, int]]] = []
    conflicts: list[str] = []
    for relative in sorted(source_files - {SELF}):
        current_value = read_relative(target_fd, safe_suffix(relative))
        current = (checksum(current_value[0]), current_value[1]) if current_value else None
        expected = (source_sums[relative], snapshot[relative][1])
        if current == expected: continue
        if relative in prior_files:
            if current is not None and current[0] != prior_sums.get(relative): conflicts.append(f"locally modified owned file: {relative}")
        elif current is not None: conflicts.append(f"conflicting existing file: {relative}")
        copies.append((relative, current))
    for relative in sorted(prior_files - source_files - {SELF}):
        current_value = read_relative(target_fd, safe_suffix(relative))
        if current_value is None: continue
        current = (checksum(current_value[0]), current_value[1])
        if current[0] != prior_sums.get(relative): conflicts.append(f"locally modified owned file: {relative}")
        removals.append((relative, current))
    manifest_current = (checksum(prior_manifest_bytes), prior_value[1]) if prior_manifest_bytes is not None and prior_value is not None else None
    manifest_changed = prior_manifest_bytes != source_manifest_bytes or (prior_value is not None and prior_value[1] != manifest_mode)
    if prior_manifest is None and prior_manifest_bytes is not None: conflicts.append("conflicting existing file: .agents/manifest.json")
    if conflicts and not replace:
        raise InstallError("refusing conflicts without --replace:\n  " + "\n  ".join(conflicts))

    operations = [f"REMOVE {relative}" for relative, _ in removals]
    operations += [f"INSTALL {relative}" for relative, _ in copies]
    if manifest_changed: operations.append("INSTALL .agents/manifest.json")
    if not operations:
        print("no changes — library is current"); raise SystemExit(0)
    for operation in operations: print(operation)
    if dry_run: raise SystemExit(0)

    if target_fd is None: target_fd = open_absolute_directory(target_path, create=True)
    assert target_fd is not None
    cache[()] = os.dup(target_fd)
    records: list[dict] = []

    def apply_remove_or_copy(relative: str, observed: tuple[str, int] | None, payload: tuple[bytes, int] | None) -> None:
        suffix = safe_suffix(relative)
        opened_parent, name = open_parent(target_fd, suffix, create=payload is not None, cache=cache)
        parent_key = tuple(Path(suffix).parts[:-1]); parent = cache[parent_key]
        os.close(opened_parent)
        record = {"relative": relative, "parent": parent, "name": name, "backup": None, "installed": None}
        records.append(record)
        record["backup"] = quarantine(parent, name, observed, relative) if observed is not None else None
        if record["backup"] is not None:
            captured = read_leaf(parent, record["backup"], missing_ok=False)
            assert captured is not None
            if (checksum(captured[0]), captured[1]) != observed: raise InstallError(f"destination changed after preflight: {relative}")
        if payload is not None:
            record["installed"] = (checksum(payload[0]), payload[1])
            create_file_no_replace(parent, name, payload[0], payload[1])

    try:
        for relative, observed in removals: apply_remove_or_copy(relative, observed, None)
        for relative, observed in copies: apply_remove_or_copy(relative, observed, snapshot[relative])
        if manifest_changed: apply_remove_or_copy(SELF, manifest_current, (source_manifest_bytes, manifest_mode))
    except Exception as original:
        rollback_errors = []
        for record in reversed(records):
            parent, name, backup = record["parent"], record["name"], record["backup"]
            try:
                installed = read_leaf(parent, name, missing_ok=True)
                if installed is not None:
                    if record["installed"] is None or (checksum(installed[0]), installed[1]) != record["installed"]:
                        raise InstallError("destination changed during rollback")
                    os.unlink(name, dir_fd=parent)
                if backup is not None:
                    os.link(backup, name, src_dir_fd=parent, dst_dir_fd=parent, follow_symlinks=False)
                    os.unlink(backup, dir_fd=parent)
            except Exception as error: rollback_errors.append(f"{record['relative']}: {error}")
        if rollback_errors:
            recovery_name = f".install-recovery-{secrets.token_hex(8)}.json"
            recovery = [{"relative": record["relative"], "backup": record["backup"], "originally_absent": record["backup"] is None} for record in records]
            try: create_file_no_replace(target_fd, recovery_name, (json.dumps(recovery, indent=2) + "\n").encode(), 0o600)
            except Exception: pass
            raise InstallError(f"installation failed ({original}); rollback incomplete; recovery map: {target_path / recovery_name}; errors: {rollback_errors}") from original
        if isinstance(original, InstallError): raise
        raise InstallError(f"installation failed and was rolled back: {original}") from original
    else:
        cleanup_errors = []
        for record in records:
            if record["backup"] is not None:
                try: os.unlink(record["backup"], dir_fd=record["parent"])
                except OSError as error: cleanup_errors.append(f"{record['relative']}: {error}")
        if cleanup_errors: raise InstallError(f"installation committed but backup cleanup failed: {cleanup_errors}")
except InstallError as error:
    print(f"install-library: {error}", file=sys.stderr)
    raise SystemExit(1)
finally:
    for descriptor in cache.values():
        try: os.close(descriptor)
        except OSError: pass
    if source_fd is not None:
        try: os.close(source_fd)
        except OSError: pass
    if target_fd is not None:
        try: os.close(target_fd)
        except OSError: pass
PY
