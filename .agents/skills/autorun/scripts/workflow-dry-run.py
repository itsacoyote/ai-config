#!/usr/bin/env python3
"""Executable no-op walk of the portable supervised workflow dispatch graph."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
ROOT = SKILL_DIR.parents[2]
LEASE = SKILL_DIR / "scripts/writer-lease.py"
PI_WRAPPER = SKILL_DIR / "scripts/run-pi-implementer.sh"


def verify_roles() -> None:
    subprocess.run([str(ROOT / ".agents/scripts/validate-roles.py")], cwd=ROOT, check=True, capture_output=True)


def fake_launcher(directory: Path, status: str) -> Path:
    launcher = directory / "sandbox-launcher"
    launcher.write_text(f"""#!/usr/bin/env bash
set -euo pipefail
mode=$1
shift
if [[ $mode == verify ]]; then
  digest=
  while [[ $# -gt 0 ]]; do
    if [[ $1 == --writable-paths-digest ]]; then digest=$2; shift 2; else shift; fi
  done
  printf '{{"version":1,"fresh_sandbox":true,"control_read_only":true,"scoped_writes":true,"credentials_cleared":true,"network_disabled":true,"foreground_exec":true,"writable_paths_digest":"%s"}}\\n' "$digest"
  exit 0
fi
[[ $mode == run ]] || exit 2
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
[[ $# -gt 0 ]] || exit 2
shift
printf '%s\\n' 'STATUS: {status}'
sleep 0.2
""")
    launcher.chmod(0o700)
    return launcher


def exact_status(output: str) -> str:
    statuses = [line.removeprefix("STATUS: ") for line in output.splitlines() if line.startswith("STATUS: ")]
    return statuses[0] if len(statuses) == 1 and statuses[0] in {"DONE", "DONE_WITH_CONCERNS", "NEEDS_CONTEXT", "BLOCKED"} else "BLOCKED"


def codex_noop(task: str, requested_status: str) -> tuple[str, str]:
    adapter = SKILL_DIR / "scripts/noop-codex-adapter.py"
    process = subprocess.run(
        [
            str(adapter),
            "--adapter", str(ROOT / ".codex/agents/implementer.toml"),
            "--config", str(ROOT / ".codex/config.toml"),
            "--task", task,
            "--status", requested_status,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return "codex-executable-noop-adapter", exact_status(process.stdout)


def pi_noop(task: str, requested_status: str, paths_file: Path, owner_id: str) -> tuple[str, str]:
    with tempfile.TemporaryDirectory(prefix="autorun-sandbox-") as directory:
        trusted_directory = Path(directory)
        launcher = fake_launcher(trusted_directory, requested_status)
        fake_pi = trusted_directory / "pi"
        fake_pi.write_text("#!/usr/bin/env bash\nprintf '%s\\n' 'unexpected direct pi execution' >&2\nexit 99\n")
        fake_pi.chmod(0o700)
        environment = dict(os.environ)
        environment["PATH"] = f"{trusted_directory}{os.pathsep}{environment.get('PATH', '')}"
        environment["AUTORUN_SANDBOX_LAUNCHER"] = str(launcher)
        process = subprocess.run(
            [str(PI_WRAPPER), "--owner-id", owner_id, "--writable-paths", str(paths_file), "--", task],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
        )
        if process.returncode:
            raise RuntimeError(f"Pi sandbox no-op failed: {process.stderr}")
    return "pi-sandbox-wrapper-noop-process", exact_status(process.stdout)


def walk(harness: str, task_count: int, requested_status: str) -> dict:
    verify_roles()
    events = ["Define:approved", "Research:done", "Plan:done", "PlanReview:approved"]
    active_writers = 0
    max_active_writers = 0
    dispatches = []
    with tempfile.TemporaryDirectory(prefix="autorun-scope-") as directory:
        paths_file = Path(directory) / "writable-paths.txt"
        paths_file.write_text("README.md\n")
        paths_file.chmod(0o600)
        for index in range(1, task_count + 1):
            task = f"noop-task-{index}"
            owner_id = f"dry-run-{uuid.uuid4()}"
            subprocess.run([
                str(LEASE), "--cwd", str(ROOT), "acquire", "--owner-id", owner_id,
                "--owner-pid", str(os.getpid()), "--task", task, "--pre-task-sha", "noop",
                "--writable-paths", str(paths_file),
            ], check=True, capture_output=True)
            active_writers += 1
            max_active_writers = max(max_active_writers, active_writers)
            try:
                if harness == "pi":
                    route, status = pi_noop(task, requested_status, paths_file, owner_id)
                else:
                    route, status = codex_noop(task, requested_status)
                dispatches.append({"task": task, "role": "implementer", "route": route, "status": status})
                events.extend((f"beads:{task}:in_progress", f"{harness}:implementer:{task}:{status}"))
            finally:
                active_writers -= 1
                subprocess.run([str(LEASE), "--cwd", str(ROOT), "release", "--owner-id", owner_id], check=True)
            if status != "DONE":
                events.append(f"beads:{task}:remains-in_progress")
                events.append("Workflow:exception-stop")
                break
            events.append(f"beads:{task}:closed")
        else:
            events.extend(("Validate:approved", "Document:prepared", "PR:awaiting-human"))
    return {
        "harness": harness,
        "events": events,
        "dispatches": dispatches,
        "max_active_writers": max_active_writers,
        "active_writers_at_end": active_writers,
        "terminal_gate": events[-1],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--harness", choices=("codex", "pi"), required=True)
    parser.add_argument("--tasks", type=int, default=2)
    parser.add_argument("--worker-status", default="DONE")
    args = parser.parse_args()
    if args.tasks < 1:
        parser.error("--tasks must be positive")
    print(json.dumps(walk(args.harness, args.tasks, args.worker_status), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
