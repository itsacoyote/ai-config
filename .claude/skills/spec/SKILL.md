---
name: spec
description: Template and quality criteria for writing a 1_spec.md file. Use when ready to write the spec document after the discovery conversation is complete.
allowed-tools: Write Read
---

# Spec

Write `1_spec.md` using the template in [template.md](template.md) into the feature folder.

## Quality criteria

Each section should meet this bar before the file is written:

- **Summary** — One paragraph. A new reader with no context should understand what the feature is and why it exists.
- **Problem Statement** — Concrete. Names who is affected and how. Not "users want X" — describe the actual pain.
- **Goals** — Specific outcomes, not activities. "Users can do X" not "we will build Y".
- **Non-Goals** — Explicit. If it's not listed here, it's assumed in scope.
- **User Stories** — Cover the primary path and at least one edge case. Format: "As a [role], I want [action] so that [outcome]."
- **Requirements** — Functional facts already decided. No vague language ("should", "maybe"). Each requirement is either true or false after implementation.
- **Constraints** — Real blockers: technical limits, time, third-party dependencies. Not preferences.
- **Acceptance Criteria** — Testable. Each criterion can be marked done by a reviewer without asking the author what they meant.
- **Open Questions** — Only unresolved blockers. If the answer is known, fold it into the relevant section instead.

## What to avoid

- No TBDs, TODOs, or placeholders in the final doc.
- No contradictions between sections.
- Scope should fit a single implementation cycle — if it spans multiple independent subsystems, it needs decomposition first.
