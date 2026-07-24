#!/bin/bash
set -euo pipefail

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
export PATH

SOURCE=${HOME}/.agents/scripts/pwt
BIN_DIR=${HOME}/.local/bin
DRY_RUN=0
REPLACE_LINK=0

usage() {
  cat <<'EOF'
Usage: install-pwt.sh [--source PWT] [--bin-dir DIR] [--dry-run] [--replace-link]

Expose the installed portable pwt launcher as BIN_DIR/pwt using a stable symlink.
The default source is ~/.agents/scripts/pwt and the default bin directory is
~/.local/bin.

The installer is idempotent. It safely migrates an identical regular-file copy
while retaining a recovery backup, refuses to overwrite a different regular
file, and replaces a different symlink only when --replace-link is supplied.
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --source) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; SOURCE=$2; shift 2 ;;
    --bin-dir) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; BIN_DIR=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --replace-link) REPLACE_LINK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'install-pwt: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

PYTHON=$(command -v python3 2>/dev/null) || {
  printf '%s\n' 'install-pwt: python3 is required' >&2
  exit 1
}

"$PYTHON" -I - "$SOURCE" "$BIN_DIR" "$DRY_RUN" "$REPLACE_LINK" <<'PY'
from __future__ import annotations

import hashlib
import os
import secrets
import stat
import sys
from pathlib import Path

source_arg = sys.argv[1]
bin_dir_arg = sys.argv[2]
source: Path
bin_dir: Path
dry_run = sys.argv[3] == "1"
replace_link = sys.argv[4] == "1"
target_name = "pwt"
DIR_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
FILE_FLAGS = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)


class InstallError(Exception):
    pass


def check_directory(descriptor: int, path: Path) -> None:
    metadata = os.fstat(descriptor)
    mode = stat.S_IMODE(metadata.st_mode)
    unsafe_write = mode & 0o020 or (mode & 0o002 and not mode & stat.S_ISVTX)
    if metadata.st_uid not in {0, os.geteuid()} or unsafe_write:
        raise InstallError(f"directory has unsafe ownership or permissions: {path}")


def check_private_directory(descriptor: int, path: Path) -> None:
    metadata = os.fstat(descriptor)
    if metadata.st_uid not in {0, os.geteuid()} or stat.S_IMODE(metadata.st_mode) & 0o022:
        raise InstallError(f"directory has unsafe ownership or permissions: {path}")


def open_directory(path: Path, *, create: bool, missing_ok: bool = False) -> int | None:
    if not path.is_absolute():
        raise InstallError(f"directory path must be absolute: {path}")
    descriptor = os.open(path.anchor, DIR_FLAGS)
    check_directory(descriptor, Path(path.anchor))
    current = Path(path.anchor)
    try:
        for part in path.parts[1:]:
            current /= part
            try:
                child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            except FileNotFoundError:
                if missing_ok and not create:
                    os.close(descriptor)
                    return None
                if not create:
                    raise InstallError(f"directory does not exist: {path}")
                try:
                    os.mkdir(part, 0o755, dir_fd=descriptor)
                except FileExistsError:
                    pass
                child = os.open(part, DIR_FLAGS, dir_fd=descriptor)
            except OSError as error:
                raise InstallError(
                    f"unsafe or non-directory path component in {path}: {part}: {error}"
                ) from error
            try:
                check_directory(child, current)
            except Exception:
                os.close(child)
                raise
            os.close(descriptor)
            descriptor = child
        return descriptor
    except Exception:
        try:
            os.close(descriptor)
        except OSError:
            pass
        raise


def read_regular(parent_fd: int, name: str, *, label: str) -> tuple[bytes, os.stat_result]:
    try:
        descriptor = os.open(name, FILE_FLAGS, dir_fd=parent_fd)
    except OSError as error:
        raise InstallError(f"cannot safely open {label}: {error}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise InstallError(f"{label} is not a regular file")
        chunks = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(descriptor)
        identity = (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
        if identity != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise InstallError(f"{label} changed while reading")
        return b"".join(chunks), before
    finally:
        os.close(descriptor)


def target_state(parent_fd: int, name: str):
    try:
        metadata = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(metadata.st_mode):
        return (
            "link",
            os.readlink(name, dir_fd=parent_fd),
            metadata.st_uid,
            metadata.st_dev,
            metadata.st_ino,
        )
    if stat.S_ISREG(metadata.st_mode):
        data, opened = read_regular(parent_fd, name, label=str(bin_dir / name))
        return (
            "file",
            hashlib.sha256(data).hexdigest(),
            stat.S_IMODE(opened.st_mode),
            data,
            opened.st_uid,
            opened.st_dev,
            opened.st_ino,
        )
    return ("other", stat.S_IFMT(metadata.st_mode))


def create_link(parent_fd: int, name: str) -> None:
    try:
        os.symlink(str(source), name, dir_fd=parent_fd)
    except FileExistsError as error:
        raise InstallError(f"destination appeared during installation: {bin_dir / name}") from error


def restore_retained_backup(parent_fd: int, backup: str) -> str:
    try:
        os.link(
            backup,
            target_name,
            src_dir_fd=parent_fd,
            dst_dir_fd=parent_fd,
            follow_symlinks=False,
        )
    except FileExistsError:
        return "destination is occupied"
    except OSError as error:
        return f"automatic restore failed: {error}"
    return "destination restored; backup retained"


source_parent_fd = bin_fd = None
try:
    try:
        source = Path(source_arg).expanduser().absolute()
        bin_dir = Path(bin_dir_arg).expanduser().absolute()
    except (RuntimeError, ValueError) as error:
        raise InstallError(f"invalid source or bin directory path: {error}") from error

    source_parent_fd = open_directory(source.parent, create=False)
    assert source_parent_fd is not None
    check_private_directory(source_parent_fd, source.parent)
    source_data, source_metadata = read_regular(
        source_parent_fd, source.name, label=f"launcher {source}"
    )
    if source_metadata.st_uid not in {0, os.geteuid()}:
        raise InstallError(f"launcher has unsafe ownership: {source}")
    if stat.S_IMODE(source_metadata.st_mode) & 0o022:
        raise InstallError(f"launcher is group- or world-writable: {source}")
    if not stat.S_IMODE(source_metadata.st_mode) & 0o111:
        raise InstallError(f"launcher is not executable: {source}")

    bin_fd = open_directory(bin_dir, create=False, missing_ok=True)
    if bin_fd is not None:
        check_private_directory(bin_fd, bin_dir)
    observed = target_state(bin_fd, target_name) if bin_fd is not None else None
    expected_link = str(source)

    if observed is not None and observed[:2] == ("link", expected_link):
        if observed[2] not in {0, os.geteuid()}:
            raise InstallError(f"existing launcher symlink has unsafe ownership: {bin_dir / target_name}")
        print(f"no changes — {bin_dir / target_name} already links to {source}")
        raise SystemExit(0)

    operation = "LINK"
    replace_existing = False
    if observed is not None:
        if observed[0] == "file":
            if (observed[5], observed[6]) == (source_metadata.st_dev, source_metadata.st_ino):
                raise InstallError(f"launcher source and destination must differ: {source}")
            if observed[3] != source_data:
                raise InstallError(f"refusing to overwrite a different regular file: {bin_dir / target_name}")
            operation = "MIGRATE"
            replace_existing = True
        elif observed[0] == "link":
            if not replace_link:
                raise InstallError(
                    f"refusing to replace symlink to {observed[1]!r} without --replace-link: "
                    f"{bin_dir / target_name}"
                )
            operation = "RELINK"
            replace_existing = True
        else:
            raise InstallError(f"refusing to replace a non-file destination: {bin_dir / target_name}")

    print(f"{operation} {bin_dir / target_name} -> {source}")
    if dry_run:
        raise SystemExit(0)

    if bin_fd is None:
        bin_fd = open_directory(bin_dir, create=True)
        assert bin_fd is not None
        check_private_directory(bin_fd, bin_dir)
    backup = None
    if replace_existing:
        backup = f".install-pwt-backup-{secrets.token_hex(16)}"
        try:
            os.rename(target_name, backup, src_dir_fd=bin_fd, dst_dir_fd=bin_fd)
        except FileNotFoundError as error:
            raise InstallError(f"destination disappeared during installation: {bin_dir / target_name}") from error
        if target_state(bin_fd, backup) != observed:
            restore = restore_retained_backup(bin_fd, backup)
            raise InstallError(
                f"destination changed during installation; retained backup: {bin_dir / backup}; {restore}"
            )
    try:
        create_link(bin_fd, target_name)
    except Exception as error:
        if backup is not None:
            restore = restore_retained_backup(bin_fd, backup)
            raise InstallError(
                f"installation failed ({error}); retained backup: {bin_dir / backup}; {restore}"
            ) from error
        if isinstance(error, InstallError):
            raise
        raise InstallError(f"installation failed: {error}") from error
    if backup is not None:
        print(f"BACKUP {bin_dir / backup}")
except InstallError as error:
    print(f"install-pwt: {error}", file=sys.stderr)
    raise SystemExit(1)
except OSError as error:
    print(f"install-pwt: filesystem operation failed: {error}", file=sys.stderr)
    raise SystemExit(1)
finally:
    for descriptor in (source_parent_fd, bin_fd):
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
PY
