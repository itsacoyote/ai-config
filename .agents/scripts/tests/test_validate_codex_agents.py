#!/usr/bin/env python3
from __future__ import annotations

import json
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ROLES_PATH = ROOT / ".agents" / "agents" / "roles.json"
CODEX_DIR = ROOT / ".codex"


class CodexAdapterContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads(ROLES_PATH.read_text())
        cls.roles = {role["name"]: role for role in cls.manifest["roles"]}
        cls.adapters = {
            path.stem: tomllib.loads(path.read_text())
            for path in sorted((CODEX_DIR / "agents").glob("*.toml"))
        }

    def test_codex_adapter_covers_every_neutral_role(self) -> None:
        self.assertEqual(set(self.roles), set(self.adapters))
        for name, role in self.roles.items():
            adapter = self.adapters[name]
            self.assertEqual(name, adapter["name"])
            self.assertEqual(role["description"], adapter["description"])
            instructions = adapter["developer_instructions"]
            self.assertIn(f".agents/agents/{role['prompt']}", instructions)
            self.assertIn(".agents/agents/roles.json", instructions)
            for skill in role["skills"]:
                self.assertIn(f".agents/skills/{skill}/SKILL.md", instructions)

    def test_config_bounds_agent_concurrency_and_depth(self) -> None:
        config = tomllib.loads((CODEX_DIR / "config.toml").read_text())
        self.assertGreater(config["agents"]["max_threads"], 0)
        self.assertEqual(1, config["agents"]["max_depth"])

    def test_nonexecuting_roles_use_read_only_sandbox(self) -> None:
        for name, role in self.roles.items():
            if role["mode"] == "read-only":
                self.assertEqual("read-only", self.adapters[name].get("sandbox_mode"), name)

    def test_qa_allows_artifacts_but_returns_schema_valid_results_instead_of_source_edits(self) -> None:
        adapter = self.adapters["qa-review"]
        self.assertEqual("workspace-write", adapter.get("sandbox_mode"))
        instructions = adapter["developer_instructions"]
        self.assertIn("test and evidence artifacts only", instructions)
        self.assertIn("Never edit source or test definitions", instructions)
        self.assertIn(".agents/agents/qa-result.schema.json", instructions)
        self.assertIn("validate-qa-result.py", instructions)

    def test_implementer_inherits_parent_permissions(self) -> None:
        adapter = self.adapters["implementer"]
        self.assertNotIn("sandbox_mode", adapter)
        self.assertIn("Inherit the parent session's sandbox and approval policy", adapter["developer_instructions"])

    def test_codex_agents_do_not_pin_provider_models(self) -> None:
        for name, adapter in self.adapters.items():
            self.assertNotIn("model", adapter, name)
            self.assertNotIn("model_reasoning_effort", adapter, name)

    def test_adapters_contain_only_supported_policy_fields(self) -> None:
        allowed = {"name", "description", "developer_instructions", "sandbox_mode"}
        for name, adapter in self.adapters.items():
            self.assertLessEqual(set(adapter), allowed, name)

    def test_root_guidance_points_to_codex_and_neutral_contracts(self) -> None:
        guidance = (ROOT / "AGENTS.md").read_text()
        self.assertIn(".codex/agents/", guidance)
        self.assertIn(".agents/agents/", guidance)


if __name__ == "__main__":
    unittest.main()
