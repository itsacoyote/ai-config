import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = ROOT / "scripts" / "validate-qa-result.py"
SCHEMA_PATH = ROOT / "agents" / "qa-result.schema.json"


def load_validator():
    spec = importlib.util.spec_from_file_location("validate_qa_result", VALIDATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class QaResultContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.validator = load_validator()

    def result(self, verdict="APPROVED", attempt=1, **overrides):
        value = {
            "schema_version": 1,
            "verdict": verdict,
            "attempt": attempt,
            "summary": "QA completed",
            "evidence": ["tests passed"],
            "failing_command": None,
            "affected_paths": [],
            "implementer_instructions": None,
            "blocker": None,
        }
        value.update(overrides)
        return value

    def test_schema_defines_exact_version_and_verdict_enum(self):
        schema = json.loads(SCHEMA_PATH.read_text())
        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)
        self.assertEqual(
            schema["properties"]["verdict"]["enum"],
            ["APPROVED", "FIX_REQUIRED", "BLOCKED"],
        )

    def test_approved_stops_successfully(self):
        result = self.result()
        self.validator.validate_result(result)
        self.assertEqual(self.validator.next_action(result), "PASS")

    def test_actionable_fix_required_dispatches_before_attempt_three(self):
        result = self.result(
            "FIX_REQUIRED",
            attempt=2,
            failing_command="npm test",
            evidence=["expected 2, received 1"],
            affected_paths=["src/counter.ts"],
            implementer_instructions="Correct the counter and update its regression test.",
        )
        self.validator.validate_result(result)
        self.assertEqual(self.validator.next_action(result), "DISPATCH_IMPLEMENTER")

    def test_fix_required_at_attempt_three_blocks_without_dispatch(self):
        result = self.result(
            "FIX_REQUIRED",
            attempt=3,
            failing_command="npm test",
            evidence=["still failing"],
            affected_paths=["src/counter.ts"],
            implementer_instructions="Correct the remaining failure.",
        )
        self.validator.validate_result(result)
        self.assertEqual(self.validator.next_action(result), "BLOCK")

    def test_blocked_stops_and_surfaces_blocker(self):
        result = self.result("BLOCKED", blocker="Browser service is unavailable")
        self.validator.validate_result(result)
        self.assertEqual(self.validator.next_action(result), "BLOCK")

    def test_fix_required_rejects_missing_actionable_fields(self):
        result = self.result("FIX_REQUIRED")
        with self.assertRaisesRegex(ValueError, "failing_command"):
            self.validator.validate_result(result)

    def test_invalid_and_unknown_results_block(self):
        for result in (
            self.result("UNKNOWN"),
            self.result(attempt=4),
            {"schema_version": 1},
        ):
            with self.subTest(result=result):
                with self.assertRaises(ValueError):
                    self.validator.validate_result(result)
                self.assertEqual(self.validator.safe_next_action(result), "BLOCK")

    def test_legacy_verdict_mapping_is_explicit(self):
        self.assertEqual(self.validator.map_legacy_verdict("Approved"), "APPROVED")
        self.assertEqual(self.validator.map_legacy_verdict("Gaps"), "FIX_REQUIRED")
        self.assertEqual(self.validator.map_legacy_verdict("Blocked"), "BLOCKED")
        with self.assertRaises(ValueError):
            self.validator.map_legacy_verdict("Maybe")


if __name__ == "__main__":
    unittest.main()
