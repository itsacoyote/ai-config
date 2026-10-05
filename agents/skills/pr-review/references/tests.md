# Tests Pass

Review whether the PR's diff actually covers the behavior it changes. Read-only: report gaps,
don't write or run tests yourself.

## Coverage of the change

Does each changed or added behavior have a test? Are the happy path, boundaries (empty, zero,
max, off-by-one), and error/failure cases covered for what changed? Where a bug is being
fixed, is there a regression test that would fail without the fix?

## Meaningfulness

Do the tests assert real behavior — inputs, outputs, effects — not mock return values or
implementation details? Flag a test that mocks so much it proves nothing, or that would still
pass if the code under test were deleted or gutted. Expected values should come from an
independent source of truth (a known-good literal, a spec), not be recomputed the same way the
code does it (tautological).

## What's missing

Untested branches the diff introduces, error paths with no coverage, changed behavior whose
existing tests weren't updated to match.

## Right level

Judge whether the test is at the right level: unit for logic/edge cases, integration for
wiring/contracts/data flow, e2e only for critical user journeys. Don't accept an e2e test where
a unit test would do, and don't accept over-mocked "integration" tests that prove nothing real.

## Determinism

Flag tests with uncontrolled time/randomness/ordering, shared mutable state between tests, or
async assertions missing an await — these produce false passes.

## Scope

Stay scoped to this PR's change: review the tests the diff touches and the coverage of the
behavior it alters. Read surrounding files only to judge whether a changed behavior is
actually exercised.

If the diff is empty, docs-only, or nothing is missing, say so plainly — don't manufacture
filler findings.

## Finding format

Order most severe first. For each:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:line (for missing coverage, the untested source line the test should
  exercise)
- **What** — the gap or weak test
- **Why** — the regression or bug this lets through
- **Suggested comment text** — the missing or stronger test, described as text ready to post
