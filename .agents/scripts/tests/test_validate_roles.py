#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = ROOT / ".agents" / "scripts" / "validate-roles.py"
SPEC = importlib.util.spec_from_file_location("validate_roles", VALIDATOR_PATH)
assert SPEC and SPEC.loader
validate_roles = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate_roles)

EXPECTED_ROLES = {
    "design-review", "efficiency-review", "implementer", "plan-review",
    "pr-context", "pr-security", "pr-tests", "qa-review",
    "research-history", "research-libraries", "research-patterns",
    "research-reuse", "research-risks", "security-scan", "senior-review",
}


class RoleContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest_path = ROOT / ".agents" / "agents" / "roles.json"
        self.manifest = json.loads(self.manifest_path.read_text())

    def validate_manifest(self, manifest: dict) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "roles.json"
            path.write_text(json.dumps(manifest))
            return validate_roles.validate(ROOT, path)

    def role(self, name: str) -> dict:
        return next(role for role in self.manifest["roles"] if role["name"] == name)

    def test_accepts_every_declared_neutral_role(self) -> None:
        self.assertEqual(EXPECTED_ROLES, {role["name"] for role in self.manifest["roles"]})
        self.assertEqual([], validate_roles.validate(ROOT, self.manifest_path))

    def test_rejects_unknown_fields_modes_and_duplicate_names(self) -> None:
        manifest = json.loads(json.dumps(self.manifest))
        manifest["roles"][0]["model"] = "provider-alias"
        manifest["roles"][1]["mode"] = "admin"
        manifest["roles"][2]["name"] = manifest["roles"][3]["name"]
        errors = self.validate_manifest(manifest)
        self.assertTrue(any("unknown fields" in error for error in errors))
        self.assertTrue(any("invalid mode" in error for error in errors))
        self.assertTrue(any("duplicate role name" in error for error in errors))

    def test_rejects_missing_prompts_skills_and_references(self) -> None:
        manifest = json.loads(json.dumps(self.manifest))
        manifest["roles"][0]["prompt"] = "missing.md"
        manifest["roles"][1]["skills"] = ["missing-skill"]
        errors = self.validate_manifest(manifest)
        self.assertTrue(any("missing prompt" in error for error in errors))
        self.assertTrue(any("missing skill" in error for error in errors))

    def test_read_only_roles_prohibit_source_and_artifact_writes(self) -> None:
        for role in self.manifest["roles"]:
            if role["mode"] == "read-only":
                self.assertNotIn("source-write", role["tools"])
                self.assertNotIn("test-artifact-write", role["tools"])
                self.assertNotIn("evidence-artifact-write", role["tools"])
                prompt = (ROOT / ".agents" / "agents" / role["prompt"]).read_text()
                self.assertIn("Writes: none.", prompt)

    def test_verification_roles_limit_writes_to_test_and_evidence_artifacts(self) -> None:
        role = self.role("qa-review")
        self.assertEqual("verification", role["mode"])
        self.assertNotIn("source-write", role["tools"])
        self.assertLessEqual(
            {tool for tool in role["tools"] if tool.endswith("-write")},
            {"test-artifact-write", "evidence-artifact-write"},
        )

    def test_qa_returns_versioned_result_envelopes_without_editing_source(self) -> None:
        role = self.role("qa-review")
        prompt = (ROOT / ".agents" / "agents" / role["prompt"]).read_text()
        self.assertIn("schema_version", prompt)
        self.assertIn("Never edit source or test definitions", prompt)

    def test_qa_role_declares_the_prerequisite_qa_result_schema(self) -> None:
        self.assertEqual("qa-result.schema.json", self.manifest["contracts"]["qa_result"])
        prompt = (ROOT / ".agents" / "agents" / self.role("qa-review")["prompt"]).read_text()
        self.assertIn("qa-result.schema.json", prompt)

    def test_qa_role_documents_actions_for_approved_fix_required_and_blocked(self) -> None:
        prompt = (ROOT / ".agents" / "agents" / self.role("qa-review")["prompt"]).read_text()
        for text in ("APPROVED → PASS", "FIX_REQUIRED → DISPATCH_IMPLEMENTER", "BLOCKED → BLOCK"):
            self.assertIn(text, prompt)

    def test_qa_role_maps_existing_gaps_to_fix_required(self) -> None:
        prompt = (ROOT / ".agents" / "agents" / self.role("qa-review")["prompt"]).read_text()
        self.assertIn("Gaps → FIX_REQUIRED", prompt)

    def test_implementer_is_the_only_source_editing_role(self) -> None:
        editors = [role["name"] for role in self.manifest["roles"] if "source-write" in role["tools"]]
        self.assertEqual(["implementer"], editors)
        self.assertEqual("implementation", self.role("implementer")["mode"])


if __name__ == "__main__":
    unittest.main()
