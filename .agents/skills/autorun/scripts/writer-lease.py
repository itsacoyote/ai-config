#!/usr/bin/env python3
"""Cross-harness, per-worktree writer lease for autorun implementation workers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

LOCK_NAME = "autorun-writer.lock"
OWNER_FILE = "owner.json"


def git_root(cwd: Path) -> Path:
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=cwd, check=True, text=True, capture_output=True)
    return Path(result.stdout.strip()).resolve()


def git_lock_path(cwd: Path) -> Path:
    result = subprocess.run(["git", "rev-parse", "--git-path", LOCK_NAME], cwd=cwd, check=True, text=True, capture_output=True)
    path = Path(result.stdout.strip())
    return (cwd / path).resolve() if not path.is_absolute() else path.resolve()


def alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def validate_paths_file(path: Path, worktree: Path) -> tuple[Path, str]:
    if path.is_symlink():
        raise RuntimeError("writable-paths file must not be a symlink")
    resolved = path.resolve(strict=True)
    metadata = resolved.stat()
    if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) & 0o022:
        raise RuntimeError("writable-paths file has unsafe owner or permissions")
    lines = resolved.read_text().splitlines()
    if not lines:
        raise RuntimeError("writable-paths file is empty")
    for value in lines:
        candidate = Path(value)
        if not value or candidate.is_absolute() or ".." in candidate.parts:
            raise RuntimeError(f"unsafe writable path: {value!r}")
        contained = (worktree / candidate).resolve(strict=False)
        try:
            contained.relative_to(worktree)
        except ValueError as error:
            raise RuntimeError(f"writable path escapes worktree: {value}") from error
    digest = hashlib.sha256(resolved.read_bytes()).hexdigest()
    return resolved, f"sha256:{digest}"


def read_owner(lock: Path) -> dict:
    try:
        value = json.loads((lock / OWNER_FILE).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid writer lease metadata: {error}") from error
    if not isinstance(value, dict) or value.get("version") != 1:
        raise RuntimeError("invalid writer lease metadata")
    return value


def write_owner(lock: Path, value: dict) -> None:
    temporary = lock / f".{OWNER_FILE}.tmp"
    temporary.write_text(json.dumps(value, sort_keys=True) + "\n")
    temporary.replace(lock / OWNER_FILE)


def require_owner(owner: dict, owner_id: str) -> None:
    if owner.get("owner_id") != owner_id:
        raise RuntimeError("writer lease owner mismatch")


def acquire(args: argparse.Namespace) -> int:
    worktree = git_root(args.cwd)
    paths_file, paths_digest = validate_paths_file(args.writable_paths, worktree)
    lock = git_lock_path(args.cwd)
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        owner = read_owner(lock)
        state = "alive" if alive(owner.get("owner_pid")) or alive(owner.get("worker_pid")) else "stale"
        raise RuntimeError(f"writer lease already exists ({state}): {lock}")
    write_owner(lock, {
        "version": 1,
        "owner_id": args.owner_id,
        "owner_pid": args.owner_pid,
        "task_id": args.task,
        "pre_task_sha": args.pre_task_sha,
        "worker_pid": None,
        "writable_paths_file": str(paths_file),
        "writable_paths_digest": paths_digest,
    })
    print(lock)
    return 0


def attach(args: argparse.Namespace) -> int:
    lock = git_lock_path(args.cwd)
    owner = read_owner(lock)
    require_owner(owner, args.owner_id)
    if owner.get("worker_pid") and alive(owner["worker_pid"]):
        raise RuntimeError("writer lease already has a live worker")
    if not alive(args.worker_pid):
        raise RuntimeError("worker PID is not alive")
    owner["worker_pid"] = args.worker_pid
    write_owner(lock, owner)
    return 0


def release(args: argparse.Namespace) -> int:
    lock = git_lock_path(args.cwd)
    owner = read_owner(lock)
    require_owner(owner, args.owner_id)
    if alive(owner.get("worker_pid")):
        raise RuntimeError("cannot release writer lease while worker is alive")
    shutil.rmtree(lock)
    return 0


def break_stale(args: argparse.Namespace) -> int:
    lock = git_lock_path(args.cwd)
    owner = read_owner(lock)
    if alive(owner.get("owner_pid")) or alive(owner.get("worker_pid")):
        raise RuntimeError("cannot break a live writer lease")
    shutil.rmtree(lock)
    return 0


def status(args: argparse.Namespace) -> int:
    owner = read_owner(git_lock_path(args.cwd))
    owner["owner_alive"] = alive(owner.get("owner_pid"))
    owner["worker_alive"] = alive(owner.get("worker_pid"))
    print(json.dumps(owner, sort_keys=True))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--cwd", type=Path, default=Path.cwd())
    commands = root.add_subparsers(dest="command", required=True)
    acquire_parser = commands.add_parser("acquire")
    acquire_parser.add_argument("--owner-id", required=True)
    acquire_parser.add_argument("--owner-pid", required=True, type=int)
    acquire_parser.add_argument("--task", required=True)
    acquire_parser.add_argument("--pre-task-sha", required=True)
    acquire_parser.add_argument("--writable-paths", required=True, type=Path)
    acquire_parser.set_defaults(handler=acquire)
    attach_parser = commands.add_parser("attach-worker")
    attach_parser.add_argument("--owner-id", required=True)
    attach_parser.add_argument("--worker-pid", required=True, type=int)
    attach_parser.set_defaults(handler=attach)
    release_parser = commands.add_parser("release")
    release_parser.add_argument("--owner-id", required=True)
    release_parser.set_defaults(handler=release)
    commands.add_parser("break-stale").set_defaults(handler=break_stale)
    commands.add_parser("status").set_defaults(handler=status)
    return root


def main() -> int:
    args = parser().parse_args()
    args.cwd = args.cwd.resolve()
    try:
        return args.handler(args)
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"writer-lease: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
