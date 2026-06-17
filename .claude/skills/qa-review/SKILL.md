---
name: qa-review
description: Use to verify a change is actually tested — test coverage, test quality, and that the spec's user stories map to real tests. Use during the Validate step, after senior-review, before a change ships.
allowed-tools: Read Bash(git diff *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(npx *) Bash(make *) Bash(find *) Bash(grep *)
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
- **Suite runs and fails:** diagnose, decide whether the bug is in production code or the test, fix it (never weaken assertions, never skip/quarantine), commit (`fix(...)` or `test(...)`), and re-run — up to 3 attempts, then stop and report.

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

## Verdict

- **Approved** — e2e green (or absent-and-noted), coverage adequate on the paths that matter, no gaps. State what was verified in a sentence or two.
- **Gaps** — list each: type (unit/integration/e2e), what's missing (the specific behavior/story/path), and the test required (what it must assert).
- **Blocked** — e2e couldn't reach green after 3 attempts, or a required runtime is missing. Report the per-attempt log; don't approve.

File an issue per gap linked to the feature epic/task (see [`.claude/references/beads.md`](../../references/beads.md)).

## Non-negotiables

No coverage theater. No e2e that bypasses the real interface. No unit test whose subject is a mock. Making a red test green by skipping, deleting, or weakening it is not a fix — `.skip`/`.only`/`xit`/`test.skip`/deletion/weakened assertions are forbidden as a path to green.
