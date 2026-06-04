---
name: writing-tests
description: Use when writing, updating, or reviewing tests — adding tests for new code, writing a regression test for a bug, changing behavior that existing tests cover, or deciding what and how much to test.
---

# Writing Tests

## Overview

Good tests catch regressions and document intended behavior. They test **what** code does (observable behavior), not **how** it does it — so they survive refactors and fail only when behavior actually breaks. This skill is the judgment layer (what to test, at what level, how much). For concrete syntax — structure, assertions, mocking, React/API/E2E examples, and the full anti-pattern table — see [`.claude/references/testing-patterns.md`](../../references/testing-patterns.md).

## When to Use

- Adding tests for new code or a new feature
- Writing a regression test after fixing a bug (see `debugging-and-error-recovery`)
- Changing behavior that existing tests cover (update the tests with the change)
- Reviewing whether a test is actually good

**When NOT to use:** Throwaway spikes/prototypes you'll delete, or third-party/generated code you don't own. Match test rigor to the blast radius — a payment path earns more than an internal one-off script.

## Test Behavior, Not Implementation

Assert on inputs, outputs, and observable effects — not internal calls, private state, or structure.

- Good: "creates a task with pending status" → asserts the returned task.
- Bad: asserts that an internal helper was called in a particular order.

Implementation-detail tests break on every refactor and give false confidence.

## Test at the Right Level

| Level | Scope | Use for |
|---|---|---|
| Unit | one function/module in isolation | logic, edge cases, pure transforms |
| Integration | several units + real boundaries (DB, API) | wiring, contracts, data flow |
| E2E | the whole app through the UI | critical user journeys only |

Favor many fast unit tests, fewer integration tests, a handful of E2E (the pyramid). Don't reach for E2E what a unit test can cover; don't mock so much in a "unit" test that it proves nothing real.

## Cover the Cases That Matter

For the unit under test, cover the **happy path**, the **boundaries** (empty, zero, max, off-by-one), and the **error/failure** cases (invalid input, thrown errors, rejected promises). A suite that only covers the happy path is decoration.

## Make Tests Deterministic

Flaky tests are worse than no tests — they train people to ignore failures.

- Control time, randomness, and ordering (inject or mock them).
- No shared mutable state between tests; set up and tear down per test.
- Always `await` async assertions.

## Mock Only at Boundaries

Mock the edges (DB, network, filesystem, external APIs, the clock). Don't mock your own business logic, pure functions, or data transforms — mocking those means the test proves nothing. See the mock-vs-don't-mock table in the reference.

## Write a Regression Test for Every Bug

A bug fix isn't done until a test exists that **fails without the fix and passes with it**. This is the handoff from `debugging-and-error-recovery`'s "Guard Against Recurrence" step.

## Test-First When It Pays

For non-trivial or correctness-critical logic, write the failing test first (red → green → refactor). A failing test is a concrete specification and a disproof attempt — it catches "I built the wrong thing" before you've built it. Skip the ceremony for trivial, obviously-correct code.

## Coverage

Coverage is a flashlight, not a goal. Use it to find untested branches, not to chase 100%. Meaningful assertions on the paths that matter beat high coverage with weak assertions.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The code is simple, it doesn't need tests" | Simple code breaks too, and tests document intent. Test the behavior that matters. |
| "I'll add tests later" | Later rarely comes. Untested code calcifies and gets risky to change. |
| "Mocking everything makes it a unit test" | Mock the boundaries only. Mock the logic and the test proves nothing. |
| "100% coverage means it's well tested" | Coverage measures execution, not assertion quality. A covered line with no real assert is untested. |
| "The test is flaky, just re-run it" | Flakiness hides real bugs and erodes trust. Fix the determinism. |

## Red Flags

- Tests that break on every refactor (testing implementation details)
- Happy-path-only suites; no error or boundary cases
- `test.skip` or commented-out tests left in the codebase
- Shared state leaking between tests
- Async tests without `await` (false passes)
- Snapshot tests no one reviews

The reference has the full anti-pattern table.

## Verification

After writing tests:

- [ ] Each test asserts behavior (inputs/outputs/effects), not implementation
- [ ] Happy path, boundaries, and error cases are covered for the unit
- [ ] Tests are deterministic (time/randomness/order controlled, no shared state)
- [ ] Mocks are at boundaries only
- [ ] Every fixed bug has a regression test that fails without the fix
- [ ] Tests pass — and they fail when you deliberately break the code

Stack note: the reference examples are Jest / Testing Library / supertest / Playwright; the principles are universal — translate them to your stack's test runner.
