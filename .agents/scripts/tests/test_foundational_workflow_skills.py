#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKILLS = ROOT / ".agents" / "skills"
NAMES = ["define", "feature-workflow", "planning-and-task-breakdown", "research", "wayfinder"]
EXPLICIT = {"define", "research", "wayfinder"}
LINK_RE = re.compile(r"\[[^]]+\]\(([^)]+)\)")


class FoundationalWorkflowSkillTest(unittest.TestCase):
    def text(self, name: str) -> str:
        return (SKILLS / name / "SKILL.md").read_text()

    def test_every_foundational_skill_has_portable_frontmatter_and_preflight(self) -> None:
        for name in NAMES:
            text = self.text(name)
            self.assertIn(f"name: {name}", text)
            self.assertRegex(text, r"(?m)^description: Use when")
            self.assertIn("category: workflow", text)
            self.assertIn("## When NOT to use", text)
            self.assertIn("../../scripts/beads-preflight.sh", text)
            self.assertIn("resolve", text[text.index("beads-preflight.sh") - 200:text.index("beads-preflight.sh") + 100])

    def test_preflight_precedes_each_skill_work(self) -> None:
        first_work = {
            "define": "## Start: branch and context",
            "feature-workflow": "## The steps",
            "planning-and-task-breakdown": "Before any code is written",
            "research": "If a spec is already in context",
            "wayfinder": "## Plan, don't do",
        }
        for name, marker in first_work.items():
            text = self.text(name)
            self.assertLess(text.index("../../scripts/beads-preflight.sh"), text.index(marker), name)

    def test_workflow_preserves_order_and_explicit_handoffs(self) -> None:
        workflow = self.text("feature-workflow")
        self.assertIn("Define → Research → Plan → Implement → Validate → Document", workflow)
        expectations = {
            "define": "Do not start Research",
            "research": "Do not start planning",
            "planning-and-task-breakdown": "Do not create code or claim tasks",
            "wayfinder": "handing one or more definable features to `define`",
        }
        for name, phrase in expectations.items():
            self.assertIn(phrase, self.text(name))
        self.assertIn("wait for explicit approval", workflow)

    def test_research_dispatches_neutral_roles_through_both_harness_paths(self) -> None:
        text = self.text("research")
        for role in ("research-reuse", "research-patterns", "research-risks", "research-libraries", "research-history"):
            self.assertIn(f"../../agents/{role}.md", text)
        self.assertIn("../../references/isolated-worker-orchestration.md", text)
        self.assertIn("`.codex/agents/`", text)
        self.assertIn("run-pi-role.sh", text)
        self.assertIn("dedicated Research session", text)
        self.assertIn("does not require a Pi subagent extension", text)

    def test_explicit_only_policy_is_complete(self) -> None:
        for name in NAMES:
            policy = SKILLS / name / "agents" / "openai.yaml"
            if name in EXPLICIT:
                self.assertEqual("policy:\n  allow_implicit_invocation: false\n", policy.read_text())
            else:
                self.assertFalse(policy.exists(), name)

    def test_all_bundled_markdown_links_resolve(self) -> None:
        for name in NAMES:
            for source in (SKILLS / name).rglob("*.md"):
                for target in LINK_RE.findall(source.read_text()):
                    if "://" in target or target.startswith(("#", "mailto:")):
                        continue
                    path = target.split("#", 1)[0]
                    if path:
                        self.assertTrue((source.parent / path).resolve().exists(), f"{source}: {target}")

    def test_slice_has_no_claude_only_dispatch_or_runtime_paths(self) -> None:
        combined = "\n".join(self.text(name) for name in NAMES)
        for forbidden in ("${CLAUDE_SKILL_DIR}", ".claude/", "Agent(...)", "Agent tool"):
            self.assertNotIn(forbidden, combined)
        self.assertNotRegex(combined, r"(?i)pi (?:subagent )?extension (?:is )?required")


if __name__ == "__main__":
    unittest.main()
