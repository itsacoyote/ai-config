#!/usr/bin/env python3

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
VALIDATOR = ROOT / ".agents/scripts/validate-library.py"
MANIFEST = ".agents/manifest.json"


class ValidateLibraryTest(unittest.TestCase):
    def run_validator(self, root: Path = ROOT) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(VALIDATOR), "--root", str(root)],
            text=True,
            capture_output=True,
        )

    def fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        shutil.copytree(ROOT / ".agents", root / ".agents")
        shutil.copytree(ROOT / ".codex", root / ".codex")
        shutil.copytree(ROOT / ".claude", root / ".claude")
        shutil.copy2(ROOT / "AGENTS.md", root / "AGENTS.md")
        return temporary, root

    def refresh_checksum(self, root: Path, relative: str) -> None:
        path = root / relative
        manifest = json.loads((root / MANIFEST).read_text())
        manifest["ownership"]["checksums"][relative] = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
        (root / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    def add_owned(self, root: Path, relative: str) -> None:
        manifest = json.loads((root / MANIFEST).read_text())
        manifest["ownership"]["files"].append(relative)
        manifest["ownership"]["files"].sort()
        manifest["ownership"]["checksums"][relative] = "sha256:" + hashlib.sha256((root / relative).read_bytes()).hexdigest()
        (root / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    def test_accepts_the_complete_portable_library(self) -> None:
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("validated 49 skills and 15 roles", result.stdout)

    def test_rejects_invalid_skill_frontmatter_or_nested_skill_layout(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        skill = root / ".agents/skills/typescript-tips/SKILL.md"
        skill.write_text(skill.read_text().replace("name: typescript-tips", "name: wrong"))
        self.refresh_checksum(root, ".agents/skills/typescript-tips/SKILL.md")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("skill", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        nested = root2 / ".agents/skills/typescript-tips/nested/SKILL.md"
        nested.parent.mkdir()
        nested.write_text("---\nname: nested\ndescription: Use when invalid.\nmetadata:\n  category: workflow\n---\n")
        self.add_owned(root2, ".agents/skills/typescript-tips/nested/SKILL.md")
        nested_result = self.run_validator(root2)
        self.assertNotEqual(nested_result.returncode, 0)
        self.assertIn("nested skill", nested_result.stderr.lower())

    def test_rejects_dead_links_and_missing_shared_dependencies(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        skill = root / ".agents/skills/typescript-tips/SKILL.md"
        skill.write_text(skill.read_text() + "\n[missing](../../references/not-there.md)\n")
        self.refresh_checksum(root, ".agents/skills/typescript-tips/SKILL.md")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertRegex(result.stderr.lower(), r"(link|missing)")

    def test_rejects_unapproved_claude_paths_or_dispatch_syntax(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        support = root / ".agents/skills/writing-skills/graphviz-conventions.dot"
        support.write_text(support.read_text() + "\n// Use .claude/foo and Agent(role='writer').\n")
        self.refresh_checksum(root, ".agents/skills/writing-skills/graphviz-conventions.dot")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("portable", result.stderr.lower())

    def test_rejects_missing_explicit_invocation_policy(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        relative = ".agents/skills/define/agents/openai.yaml"
        (root / relative).unlink()
        manifest = json.loads((root / MANIFEST).read_text())
        manifest["ownership"]["files"].remove(relative)
        del manifest["ownership"]["checksums"][relative]
        (root / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("explicit", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        policy = root2 / ".agents/skills/define/agents/openai.yaml"
        policy.write_text("policy:\n  allow_implicit_invocation: false\n  allow_implicit_invocation: true\n")
        self.refresh_checksum(root2, ".agents/skills/define/agents/openai.yaml")
        contradictory = self.run_validator(root2)
        self.assertNotEqual(contradictory.returncode, 0)
        self.assertIn("exact false-only schema", contradictory.stderr)

    def test_rejects_role_adapter_coverage_or_sandbox_mismatch(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        adapter = root / ".codex/agents/senior-review.toml"
        adapter.write_text(adapter.read_text().replace('sandbox_mode = "read-only"', 'sandbox_mode = "workspace-write"'))
        self.refresh_checksum(root, ".codex/agents/senior-review.toml")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sandbox", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        extra = root2 / ".codex/agents/extra.toml"
        extra.write_text('name = "extra"\nsandbox_mode = "read-only"\n')
        self.add_owned(root2, ".codex/agents/extra.toml")
        extra_result = self.run_validator(root2)
        self.assertNotEqual(extra_result.returncode, 0)
        self.assertIn("physical inventory", extra_result.stderr.lower())

        temporary3, root3 = self.fixture()
        self.addCleanup(temporary3.cleanup)
        manifest = json.loads((root3 / MANIFEST).read_text())
        manifest["roles"]["codex_adapters"]["senior-review"] = "../outside.toml"
        (root3 / MANIFEST).write_text(json.dumps(manifest))
        traversal = self.run_validator(root3)
        self.assertNotEqual(traversal.returncode, 0)
        self.assertIn("unsafe manifest path", traversal.stderr)

    def test_rejects_unexpected_source_bundle_drift(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        payload = root / ".agents/skills/impeccable/scripts/live-accept.mjs"
        payload.write_text(payload.read_text() + "\n// drift\n")
        self.refresh_checksum(root, ".agents/skills/impeccable/scripts/live-accept.mjs")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source parity", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        source = root2 / ".claude/skills/define/SKILL.md"
        source.write_text(source.read_text() + "\nsource drift\n")
        source_result = self.run_validator(root2)
        self.assertNotEqual(source_result.returncode, 0)
        self.assertIn("source checksum drift", source_result.stderr.lower())

    def test_rejects_stale_catalog_and_name_collisions(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        catalog = root / ".agents/catalog.md"
        catalog.write_text(catalog.read_text() + "\nstale\n")
        self.refresh_checksum(root, ".agents/catalog.md")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("catalog", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        duplicate = root2 / ".agents/skills/duplicate/SKILL.md"
        duplicate.parent.mkdir()
        duplicate.write_text(
            "---\nname: typescript-tips\ndescription: Use when testing collisions.\n"
            "metadata:\n  category: workflow\n---\n"
        )
        self.add_owned(root2, ".agents/skills/duplicate/SKILL.md")
        collision = self.run_validator(root2)
        self.assertNotEqual(collision.returncode, 0)
        self.assertRegex(collision.stderr.lower(), r"(collision|name/directory)")

    def test_manifest_covers_every_payload_file_with_a_checksum(self) -> None:
        manifest = json.loads((ROOT / MANIFEST).read_text())
        owned = set(manifest["ownership"]["files"])
        checksums = set(manifest["ownership"]["checksums"])
        actual = {"AGENTS.md"}
        actual.update(
            str(path.relative_to(ROOT)) for path in (ROOT / ".agents").rglob("*")
            if path.is_file() and "__pycache__" not in path.parts and not path.name.endswith(".pyc")
        )
        actual.update(
            str(path.relative_to(ROOT)) for path in (ROOT / ".codex").rglob("*")
            if path.is_file() and "__pycache__" not in path.parts and not path.name.endswith(".pyc")
        )
        self.assertEqual(owned, actual)
        self.assertEqual(checksums, actual - {MANIFEST})

    def test_manifest_owns_but_does_not_self_checksum(self) -> None:
        manifest = json.loads((ROOT / MANIFEST).read_text())
        self.assertIn(MANIFEST, manifest["ownership"]["files"])
        self.assertNotIn(MANIFEST, manifest["ownership"]["checksums"])
        self.assertEqual(manifest["ownership"]["self"], MANIFEST)

    def test_rejects_unsafe_paths_symlinks_and_target_script_execution(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        external = root.parent / "external-payload"
        external.write_text("external")
        payload = root / ".agents/catalog.md"
        payload.unlink(); payload.symlink_to(external)
        self.refresh_checksum(root, ".agents/catalog.md")
        symlink_result = self.run_validator(root)
        self.assertNotEqual(symlink_result.returncode, 0)
        self.assertRegex(symlink_result.stderr.lower(), r"(symlink|escapes root)")

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        marker = root2 / "executed"
        malicious = root2 / ".agents/scripts/validate-roles.py"
        malicious.write_text(f"from pathlib import Path\nPath({str(marker)!r}).write_text('ran')\n")
        self.refresh_checksum(root2, ".agents/scripts/validate-roles.py")
        safe_result = self.run_validator(root2)
        self.assertEqual(safe_result.returncode, 0, safe_result.stderr)
        self.assertFalse(marker.exists())

        temporary3, root3 = self.fixture()
        self.addCleanup(temporary3.cleanup)
        source = root3 / ".claude/skills/define/SKILL.md"
        external_source = root3 / "source-copy.md"
        external_source.write_bytes(source.read_bytes())
        source.unlink(); source.symlink_to(external_source)
        source_symlink = self.run_validator(root3)
        self.assertNotEqual(source_symlink.returncode, 0)
        self.assertIn("symlink", source_symlink.stderr.lower())

        temporary4, root4 = self.fixture()
        self.addCleanup(temporary4.cleanup)
        source_dir = root4 / ".claude/skills/define"
        external_dir = root4 / "define-copy"
        shutil.copytree(source_dir, external_dir)
        shutil.rmtree(source_dir); source_dir.symlink_to(external_dir, target_is_directory=True)
        directory_symlink = self.run_validator(root4)
        self.assertNotEqual(directory_symlink.returncode, 0)
        self.assertIn("symlink", directory_symlink.stderr.lower())

    def test_refresh_rejects_unreviewed_inventory_or_invalid_semantics(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        (root / ".agents/unreviewed.txt").write_text("new")
        inventory = subprocess.run(
            ["python3", str(VALIDATOR), "--root", str(root), "--refresh-manifest"],
            text=True, capture_output=True,
        )
        self.assertNotEqual(inventory.returncode, 0)
        self.assertIn("inventory changed", inventory.stderr.lower())
        (root / ".agents/unreviewed.txt").unlink()
        skill = root / ".agents/skills/typescript-tips/SKILL.md"
        skill.write_text(skill.read_text().replace("name: typescript-tips", "name: invalid"))
        invalid = subprocess.run(
            ["python3", str(VALIDATOR), "--root", str(root), "--refresh-manifest"],
            text=True, capture_output=True,
        )
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("skill", invalid.stderr.lower())

    def test_compatibility_matrix_values_are_validated(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        matrix = root / ".agents/compatibility.md"
        matrix.write_text(matrix.read_text().replace("| `typescript-tips` | `engineering-specialist` | Portable |", "| `typescript-tips` | `wrong` | Capability-limited |"))
        self.refresh_checksum(root, ".agents/compatibility.md")
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matrix values mismatch", result.stderr.lower())

    def test_manifest_schema_is_versioned_and_rejects_unknown_versions(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        manifest = json.loads((root / MANIFEST).read_text())
        manifest["version"] = 999
        (root / MANIFEST).write_text(json.dumps(manifest))
        result = self.run_validator(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("version", result.stderr.lower())

        temporary2, root2 = self.fixture()
        self.addCleanup(temporary2.cleanup)
        nested = json.loads((root2 / MANIFEST).read_text())
        nested["portability"]["unknown"] = True
        (root2 / MANIFEST).write_text(json.dumps(nested))
        nested_result = self.run_validator(root2)
        self.assertNotEqual(nested_result.returncode, 0)
        self.assertIn("portability schema", nested_result.stderr.lower())

        temporary3, root3 = self.fixture()
        self.addCleanup(temporary3.cleanup)
        mixed = json.loads((root3 / MANIFEST).read_text())
        mixed["installation"]["upgrade_from_manifest_sha256"] = [1, "sha256:" + "0" * 64]
        (root3 / MANIFEST).write_text(json.dumps(mixed))
        mixed_result = self.run_validator(root3)
        self.assertNotEqual(mixed_result.returncode, 0)
        self.assertNotIn("Traceback", mixed_result.stderr)
        self.assertIn("trusted prior", mixed_result.stderr.lower())


if __name__ == "__main__":
    unittest.main()
