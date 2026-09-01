---
name: qa-review
description: Independent QA review in an isolated context. Verifies a change actually works — traces the real code path and, where feasible, exercises the feature's behavior (drives the app or endpoint, or hands the developer a walkthrough to verify by eye) — and audits test coverage and quality against the spec, returning a verdict with evidence. Spawn from the main session (e.g. during Validate or a PR review).
model: opus
skills:
  - qa-review
  - writing-tests
---

# QA Review Agent

A thin wrapper around the `qa-review` skill, run in a fresh context for independent judgment. The methodology lives in the skill — this file only handles scoping and return.

## Gate

1. Determine the diff to review. Use the caller-passed diff scope if present (a pinned `<base>..<head>` range per [`../references/diff-scope.md`](../references/diff-scope.md) — `git diff <base>..<head>`); otherwise fall back to `git diff <default-branch>...HEAD` (three-dot form). Then read the spec's user stories / acceptance criteria (if a spec exists).
2. If there is no behavior to test (docs/config/formatting only), say so and stop.

## Review

Follow the `qa-review` skill end to end: run the e2e suite if one is detected (degrade gracefully when none/no runtime exists), audit coverage and test quality, review changed tests, and capture optional evidence when the app runs and a browser tool (`browser-testing-with-devtools` / Playwright) is available. If no browser tool is configured in this project, skip evidence with a note — do not hard-fail.

The skill's e2e fix loop is the one case where this agent may edit and commit code (`fix(...)` / `test(...)`). Do **not** push — the caller owns the terminal push.

## Return

Posture, severity vocab, beads, and status protocol baseline: see [`../references/review-agent-contract.md`](../references/review-agent-contract.md).

Deviations for this agent:

- **Verdict shape:** **Approved** / **Gaps** / **Blocked** (not the severity findings list). Include specifics: gaps as type + what's missing + the required test; Blocked with the per-attempt e2e log.
- **May edit and commit e2e fixes** (`fix(...)` / `test(...)` commits) — the one narrow exception to the contract's no-commit rule. Do **not** push.
