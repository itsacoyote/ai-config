import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILLS = ROOT / ".agents" / "skills"
ROLES = ROOT / ".agents" / "agents" / "roles.json"
TARGETS = ("validate", "pr-review")


class ReviewOrchestrationSkillTest(unittest.TestCase):
    def text(self, name: str) -> str:
        return (SKILLS / name / "SKILL.md").read_text()

    def test_portable_entrypoints_are_explicit_only_and_gate_beads_first(self) -> None:
        first_actions = {
            "validate": "## Mechanical checks",
            "pr-review": "## Intake",
        }
        for name in TARGETS:
            text = self.text(name)
            self.assertIn("metadata:\n  category: workflow", text)
            self.assertIn("## When NOT to use", text)
            preflight = text.index("../../scripts/beads-preflight.sh")
            self.assertLess(preflight, text.index(first_actions[name]))
            policy = (SKILLS / name / "agents" / "openai.yaml").read_text()
            self.assertIn("allow_implicit_invocation: false", policy)

    def test_validate_routes_declared_roles_through_both_harnesses(self) -> None:
        roles = {role["name"] for role in json.loads(ROLES.read_text())["roles"]}
        expected = {"senior-review", "security-scan", "design-review", "qa-review", "implementer"}
        self.assertTrue(expected <= roles)
        text = self.text("validate")
        for role in expected:
            self.assertIn(f"`{role}`", text)
        self.assertIn(".codex/agents/", text)
        self.assertIn(".agents/scripts/run-pi-role.sh", text)
        self.assertIn("isolated-worker-orchestration.md", text)
        self.assertIn("recompute", text.lower())
        self.assertIn("pinned diff scope", text.lower())

    def test_qa_fix_loop_is_schema_gated_serial_and_bounded(self) -> None:
        text = self.text("validate")
        required = (
            "qa-result.schema.json",
            "validate-qa-result.py",
            "DISPATCH_IMPLEMENTER",
            "exactly one serialized `implementer`",
            "attempt 3",
            "rerun fresh `qa-review`",
            "malformed",
            "non-actionable",
            "BLOCKED",
        )
        for phrase in required:
            self.assertIn(phrase, text)
        self.assertIsNotNone(re.search(r"FIX_REQUIRED.*attempts? 1.?2", text, re.DOTALL))
        self.assertIn("QA never edits source or test definitions", text)
        self.assertIn("implementer is the only role", text)
        self.assertIn("parent owns a QA attempt counter", text)
        self.assertIn("envelope attempt to equal", text)
        self.assertIn("Canonicalize every `affected_paths`", text)
        self.assertIn("reject absolute paths, traversal, symlink escapes", text)
        self.assertIn("never execute worker-supplied command text directly", text)
        self.assertIn("parent constructs the final bounded request", text)
        self.assertIn("Resolve `../../scripts/validate-qa-result.py`", text)

    def test_pr_scope_and_tooling_are_immutable_and_untrusted_data_is_sandboxed(self) -> None:
        text = self.text("pr-review")
        for phrase in (
            "`baseRefOid` and `headRefOid`",
            "immutable range",
            "detached at the captured `headRefOid`",
            "trusted directory outside the review target",
            "checksum manifest for every control file",
            "mount the complete snapshot read-only",
            "Before every dispatch, verify the manifest",
            "fresh external sandbox per worker",
            "A `noexec` mount is not sufficient",
            "detached PR worktree is data only",
            "Never load or execute `AGENTS.md`, `.agents/`, `.codex/`",
            "external sandbox",
            "Mount both PR data",
            "If these controls are unavailable, stop",
            "If either differs, discard curation and restart",
        ):
            self.assertIn(phrase, text)

    def test_pr_review_is_read_only_comment_only_orchestration(self) -> None:
        text = self.text("pr-review")
        for role in ("pr-context", "pr-security", "senior-review", "pr-tests", "design-review"):
            self.assertIn(f"`{role}`", text)
        self.assertIn(".codex/agents/", text)
        self.assertIn(".agents/scripts/run-pi-role.sh", text)
        self.assertIn("event", text)
        self.assertIn('`COMMENT`', text)
        self.assertIn("static", text.lower())
        self.assertIn("untrusted", text.lower())
        self.assertIn("never edit source", text.lower())
        self.assertIn("parent is the single writer", text.lower())

    def test_all_local_markdown_links_resolve(self) -> None:
        link_pattern = re.compile(r"\[[^]]+\]\(([^)]+)\)")
        for name in TARGETS:
            source = SKILLS / name / "SKILL.md"
            for target in link_pattern.findall(source.read_text()):
                if target.startswith(("http://", "https://", "#")):
                    continue
                path = target.split("#", 1)[0]
                self.assertTrue((source.parent / path).resolve().exists(), f"{source}: {target}")

    def test_slice_has_no_claude_only_runtime_contracts(self) -> None:
        forbidden = (
            "${CLAUDE_SKILL_DIR}",
            ".claude/",
            "Agent tool",
            "Agent(...)",
            "subagents can't",
            "browser MCP",
            "allowed-tools",
        )
        for name in TARGETS:
            text = self.text(name)
            for token in forbidden:
                self.assertNotIn(token, text, f"{name}: {token}")


if __name__ == "__main__":
    unittest.main()
