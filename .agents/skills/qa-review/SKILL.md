---
name: qa-review
description: Use when a behavioral change needs independent verification of test coverage, test quality, and spec-to-test mapping before it ships.
metadata:
  category: review-quality
---

# QA Review

A critical QA pass: make sure the feature is *actually* tested, not that a coverage number looks good. You know the difference between tests that verify real behavior and tests that exist to inflate a metric, and you call it out. This is the testing half of the Validate step; `senior-review` is the engineering-quality half. For what makes a good test, lean on `writing-tests` — don't restate it.

## When NOT to use

Changes with no behavior to test (docs, config, pure formatting). Otherwise, if there's logic or a user-facing change, it applies.

## Review against the spec

Pull the diff and read the spec's user stories and acceptance criteria alongside the test files. Every user-facing behavior the spec promises should have a test proving it works.

## E2E execution (graceful)

If an end-to-end suite exists, run it first. Detect the command by precedence — first match wins: `test:e2e` script → `e2e` script → `e2e` Make target → the command documented in the README.

- **No e2e configured:** record "no e2e framework configured" as a gap and move on — do **not** invent a command or hard-fail.
- **Command found but the runtime/app isn't available** (missing binary, no dev server, missing env): note exactly what's missing as a gap and continue. Don't silently pass.
- **Suite runs and fails:** diagnose whether the defect is in production code or the test, but do not edit either. Return an actionable `FIX_REQUIRED` result. The parent may dispatch exactly one serialized implementer and then rerun QA. QA remains independent by never applying its own proposed fix.

Graceful degradation is first-class: early/manual projects often have no e2e yet, and that must not block the review.

## Coverage audit

Run or inspect the coverage report if the project produces one. Identify which files/paths are uncovered. Don't accept coverage inflated by trivially-tested code while complex logic goes untested. (Treat a hard percentage gate as project policy, not a universal rule — flag weak coverage on the paths that matter.)

## Test quality

- **Unit:** tests assert real behavior, not mock return values. A test whose system-under-test is a mock is not a test — flag it. Names are assertive ("returns X when Y"), not "should". Edge cases implied by the spec are covered.
- **Integration:** verify real component interactions — data layer reads/writes/errors, API request/response shapes and status codes — not mocked interfaces.
- **E2E:** each user story maps to a test that drives the real interface (UI flow or API), covering key failure paths, not just the happy path.
- **Changed tests:** for every modified test in the diff, check the before/after — a test weakened to pass (looser assertion, broader input, skipped check, expected value changed to match wrong behavior) without a spec requirement justifying it is a defect, not a fix. Require fixing the code, not the test.

## Evidence (optional)

When the app runs and `browser-testing-with-devtools` (or Playwright) is available, capture screenshots of each user story's happy path and key error states as a human-readable record. Treat this as optional — skip with a note when the app can't be started or no browser tool is configured.

## Result envelope

Return JSON that validates against [`qa-result.schema.json`](../../agents/qa-result.schema.json). The exact verdicts and caller actions are:

- **`APPROVED`** — e2e is green (or absent and noted), coverage is adequate on important paths, and no actionable gap remains. The parent stops successfully.
- **`FIX_REQUIRED`** — a production/test defect or coverage gap has an actionable fix. Include the failing command, concrete evidence, affected paths, and bounded implementer instructions. On attempts 1–2, the parent dispatches exactly one implementation worker and reruns QA with the incremented attempt. At attempt 3, the parent blocks without another dispatch.
- **`BLOCKED`** — QA cannot proceed because required context/runtime is unavailable or a non-actionable obstacle remains. Include the blocker; the parent stops and surfaces it.

Legacy wording maps explicitly: `Approved` → `APPROVED`, `Gaps` → `FIX_REQUIRED`, and `Blocked` → `BLOCKED`. Malformed, unknown-version, or non-actionable results block without dispatching an implementer.

QA may write test/evidence artifacts produced by verification commands, but it never edits source or test definitions, commits, pushes, or writes beads. The parent owns fixes and files `finding:qa` issues for unresolved gaps using the labels registry in [`beads.md`](../../references/beads.md).

## Non-negotiables

No coverage theater. No e2e that bypasses the real interface. No unit test whose subject is a mock. Never edit source or tests during QA. A proposed fix must not make a red test green by skipping, deleting, or weakening it — `.skip`/`.only`/`xit`/`test.skip`/deletion/weakened assertions are forbidden.
