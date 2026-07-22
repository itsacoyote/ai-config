import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILLS = ROOT / ".agents" / "skills"


class SupervisedWorkflowSkillTest(unittest.TestCase):
    def text(self, name: str) -> str:
        return (SKILLS / name / "SKILL.md").read_text()

    def test_entrypoints_are_portable_explicit_only_and_beads_gated(self) -> None:
        for name, first_action in (("autorun", "## Preconditions"), ("document", "## Audit the diff")):
            text = self.text(name)
            self.assertIn("metadata:\n  category: workflow", text)
            self.assertIn("## When NOT to use", text)
            self.assertLess(text.index("../../scripts/beads-preflight.sh"), text.index(first_action))
            policy = (SKILLS / name / "agents" / "openai.yaml").read_text()
            self.assertIn("allow_implicit_invocation: false", policy)

    def test_autorun_preserves_order_human_gates_and_serial_workers(self) -> None:
        text = self.text("autorun")
        ordered = ["Define", "Research", "Plan", "Implement", "Validate", "Document"]
        positions = [text.index(step) for step in ordered]
        self.assertEqual(positions, sorted(positions))
        for phrase in (
            "approved Define spec",
            "human gate 1",
            "human gate 2",
            "exactly one `implementer`",
            "Never dispatch a second source-writing worker",
            "in_progress",
            "bd ready",
            "bd update <id> --claim",
            "bd close <id>",
            "DONE_WITH_CONCERNS",
            "NEEDS_CONTEXT",
            "BLOCKED",
            "bounded to 3",
            "Define approval: <digest>",
            "canonical atomic lease",
            "pre-task SHA",
            "prior worker may still be alive",
            "same** status handling",
            "missing, malformed, duplicated, or unknown status",
            "external sandbox",
            "scripts/writer-lease.py",
            "scripts/run-pi-implementer.sh",
            "Hold the lease through worker result validation",
            "preserve the existing persisted pre-task SHA unchanged",
        ):
            self.assertIn(phrase, text)
        self.assertIn(".codex/agents/", text)
        self.assertIn("../../scripts/run-pi-role.sh", text)
        self.assertIn("subagent-status-protocol.md", text)

    def test_document_never_bypasses_signing_or_pr_state(self) -> None:
        text = self.text("document")
        for phrase in (
            "unsigned commits",
            "git log --format='%G?'",
            "stop and ask the user to sign",
            "draft PR",
            "explicit approval",
            "never mark a PR ready",
            "never approve",
            "never merge",
            "never push unsigned",
            "git verify-commit <sha>",
            "Reject `N` (unsigned), `B` (bad), `E` (cannot check), `X`/`Y` (expired), `R` (revoked)",
        ):
            self.assertIn(phrase, text)

    def test_noop_codex_and_pi_walk_serializes_and_stops_at_pr_gate(self) -> None:
        walker = SKILLS / "autorun" / "scripts" / "workflow-dry-run.py"
        for harness in ("codex", "pi"):
            result = subprocess.run(
                [str(walker), "--harness", harness, "--tasks", "2"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=True,
            )
            walk = json.loads(result.stdout)
            self.assertEqual(walk["max_active_writers"], 1)
            self.assertEqual(walk["active_writers_at_end"], 0)
            self.assertEqual(walk["terminal_gate"], "PR:awaiting-human")
            self.assertEqual([item["role"] for item in walk["dispatches"]], ["implementer", "implementer"])
            self.assertEqual(sum(event.endswith(":closed") for event in walk["events"]), 2)
            self.assertNotIn("PR:ready", walk["events"])
            self.assertNotIn("PR:merged", walk["events"])

            malformed = subprocess.run(
                [str(walker), "--harness", harness, "--tasks", "2", "--worker-status", "MALFORMED"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=True,
            )
            blocked = json.loads(malformed.stdout)
            self.assertEqual(blocked["terminal_gate"], "Workflow:exception-stop")
            self.assertEqual(sum(event.endswith(":closed") for event in blocked["events"]), 0)

    def test_shared_writer_lease_and_pi_sandbox_wrapper_fail_closed(self) -> None:
        lease = SKILLS / "autorun" / "scripts" / "writer-lease.py"
        wrapper = SKILLS / "autorun" / "scripts" / "run-pi-implementer.sh"
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            repo = base / "repo"
            trusted = base / "trusted-bin"
            trusted.mkdir(mode=0o700)
            fake_pi = trusted / "pi"
            fake_pi.write_text("#!/usr/bin/env bash\nexit 99\n")
            fake_pi.chmod(0o700)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            owner = "test-owner"
            paths = repo / "paths.txt"
            paths.write_text("counter.py\n")
            acquire = [
                str(lease), "--cwd", str(repo), "acquire", "--owner-id", owner,
                "--owner-pid", str(os.getpid()), "--task", "task-1", "--pre-task-sha", "abc123",
                "--writable-paths", str(paths),
            ]
            subprocess.run(acquire, check=True, capture_output=True)
            duplicate = subprocess.run(acquire, text=True, capture_output=True)
            self.assertNotEqual(duplicate.returncode, 0)
            self.assertIn("already exists", duplicate.stderr)

            worker = subprocess.Popen(["sleep", "5"])
            try:
                subprocess.run([
                    str(lease), "--cwd", str(repo), "attach-worker", "--owner-id", owner,
                    "--worker-pid", str(worker.pid),
                ], check=True)
                live_release = subprocess.run(
                    [str(lease), "--cwd", str(repo), "release", "--owner-id", owner],
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(live_release.returncode, 0)
                self.assertIn("worker is alive", live_release.stderr)
            finally:
                worker.terminate()
                worker.wait()
            subprocess.run([str(lease), "--cwd", str(repo), "release", "--owner-id", owner], check=True)
            environment = dict(os.environ)
            environment["PATH"] = f"{trusted}{os.pathsep}{environment.get('PATH', '')}"
            environment.pop("AUTORUN_SANDBOX_LAUNCHER", None)
            blocked = subprocess.run(
                [str(wrapper), "--owner-id", owner, "--writable-paths", str(paths), "--", "noop"],
                cwd=repo,
                env=environment,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn("AUTORUN_SANDBOX_LAUNCHER", blocked.stderr)

            alias = repo / "paths-link.txt"
            alias.symlink_to(paths)
            symlink_scope = subprocess.run(
                [str(wrapper), "--owner-id", owner, "--writable-paths", str(alias), "--", "noop"],
                cwd=repo,
                env=environment,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(symlink_scope.returncode, 0)
            self.assertIn("must not be a symlink", symlink_scope.stderr)

    def test_all_local_markdown_links_resolve_and_no_claude_runtime_paths_remain(self) -> None:
        link_pattern = re.compile(r"\[[^]]+\]\(([^)]+)\)")
        forbidden = ("${CLAUDE_SKILL_DIR}", ".claude/", "Agent tool", "Agent(...)", "allowed-tools")
        for name in ("autorun", "document"):
            source = SKILLS / name / "SKILL.md"
            text = source.read_text()
            for token in forbidden:
                self.assertNotIn(token, text)
            for target in link_pattern.findall(text):
                if target.startswith(("http://", "https://", "#")):
                    continue
                self.assertTrue((source.parent / target.split("#", 1)[0]).resolve().exists(), f"{source}: {target}")


if __name__ == "__main__":
    unittest.main()
