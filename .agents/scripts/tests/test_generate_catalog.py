#!/usr/bin/env python3

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / ".agents/scripts/generate-catalog.py"
CATALOG = ROOT / ".agents/catalog.md"
SKILLS = ROOT / ".agents/skills"


def frontmatter(path: Path) -> str:
    text = path.read_text()
    if not text.startswith("---\n"):
        raise AssertionError(f"missing frontmatter: {path}")
    return text.split("---\n", 2)[1]


class GenerateCatalogTest(unittest.TestCase):
    def test_catalog_groups_every_skill_once_by_category(self) -> None:
        links = re.findall(r"^\- \[`([^`]+)`\]\(skills/[^)]+/SKILL\.md\)", CATALOG.read_text(), re.MULTILINE)
        expected = sorted(path.parent.name for path in SKILLS.glob("*/SKILL.md"))
        self.assertEqual(len(expected), 49)
        self.assertEqual(sorted(links), expected)
        self.assertEqual(len(links), len(set(links)))

    def test_catalog_is_sorted_deterministically(self) -> None:
        subprocess.run(["python3", str(SCRIPT), "--check"], cwd=ROOT, check=True)
        text = CATALOG.read_text()
        sections = re.findall(r"^## (.+)$", text, re.MULTILINE)
        self.assertEqual(sections, sorted(sections, key=str.casefold))
        for body in re.split(r"^## .+$", text, flags=re.MULTILINE)[1:]:
            names = re.findall(r"^\- \[`([^`]+)`\]", body, re.MULTILINE)
            self.assertEqual(names, sorted(names))

    def test_catalog_check_fails_when_generated_output_is_stale(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(SKILLS, root / ".agents/skills")
            target = root / ".agents/catalog.md"
            target.write_text("stale\n")
            result = subprocess.run(
                ["python3", str(SCRIPT), "--root", str(root), "--check"],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("stale", result.stderr.lower())

    def test_every_skill_has_string_category_metadata(self) -> None:
        for path in SKILLS.glob("*/SKILL.md"):
            header = frontmatter(path)
            match = re.search(r"^metadata:\n(?:  .+\n)*?  category: ([^\n]+)$", header, re.MULTILINE)
            self.assertIsNotNone(match, str(path))
            category = match.group(1).strip()
            self.assertRegex(category, r"^[a-z][a-z0-9-]*$")

    def test_category_must_be_a_direct_metadata_child(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            skill = root / ".agents/skills/example/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text(
                "---\nname: example\ndescription: Use when testing malformed metadata.\n"
                "metadata:\nother:\n  category: workflow\n---\n\n# Example\n"
            )
            result = subprocess.run(
                ["python3", str(SCRIPT), "--root", str(root)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("metadata", result.stderr)


if __name__ == "__main__":
    unittest.main()
