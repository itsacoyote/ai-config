---
name: implement
description: Guide a TDD implementation from a plan document. Works through each task in order — write tests first, implement, verify, commit. Includes code review checkpoints and coverage enforcement.
disable-model-invocation: true
allowed-tools: Read Edit Write Bash(*) Agent
---

# Implement

Execute an implementation plan task by task with TDD. If no plan is in context, ask the user to share one before beginning.

The plan has already made all architecture and decomposition decisions. Follow it faithfully. If something in the plan seems wrong, stop and flag it rather than improvising.

## Pre-Implementation Setup

Before writing any code:

1. **Read every file in the plan's file map** — read the current state of each file listed under New Files and Modified Files. Do not work from memory or assumptions about what's there.
2. **Run the existing test suite** — establish a baseline. Record which tests pass, which fail, and the current coverage percentage. If tests are already failing, stop and tell the user before proceeding.
3. **Note any skill recommendations** — if the plan includes a list of skills to invoke at certain tasks, note them now. You will invoke them when those tasks are reached.

## Implementation Loop

Work through tasks in the order defined in the plan. For each task:

1. **Re-read the relevant files** — always read the current file state before editing, even if you read it during setup.
2. **Write the tests** — write exactly the test cases named in the plan. Do not add tests not in the plan; do not skip tests that are. Run them and confirm they fail for the right reason.
3. **Implement** — follow the plan's implementation steps in order. Each step names a specific function, component, route, or schema — build exactly that.
4. **Run the tests** — confirm all tests for this task pass. If any fail, fix them before moving to the next task. Do not batch and fix later.
5. **Run the linter** — run the project's linter and formatter. Fix any violations before committing. Tests passing and linter failing will still break CI.
6. **Check coverage** — coverage must not drop below 80% across unit, integration, and e2e tests. If it does, add the missing coverage before committing.
7. **Commit** — use the commit message specified in the plan.

## Code Review

Track the total lines of code generated since the last code review. After every 300–500 lines, invoke the Code Reviewer agent before continuing to the next task. Pass the plan document so the Code Reviewer can check plan alignment.

**Always invoke the Code Reviewer for:**

- Security-critical code: authentication, authorization, session handling, payment processing, input validation, file uploads, cryptography, SQL or ORM queries
- Complex algorithms: non-trivial data transformations, performance-sensitive logic, concurrency
- Large refactorings: changes that touch more than 3 files or alter a shared interface

**Optionally invoke the Code Reviewer for:**

- Test code
- Low-complexity UI components
- Simple CRUD operations

**Do not invoke the Code Reviewer for:**

- Documentation changes
- Trivial bug fixes under 10 lines
- Configuration changes

When the Code Reviewer returns issues, fix all of them before continuing. When it returns approval, reset the line count and proceed. If the Code Reviewer returns the same issues after 3 fix attempts with no meaningful progress, stop — do not attempt a 4th fix. See **Escalation** below.

## Coverage Requirements

Maintain >80% test coverage throughout implementation. Coverage applies across all test types:

- **Unit tests** — individual functions, components, and modules in isolation
- **Integration tests** — interactions between modules, API endpoints, and database operations
- **E2E tests** — full user flows through the feature as described in the spec's user stories

## Escalation

If you have made 3 full attempts to resolve the same issue — whether a failing test, a linter error, or a code review finding — without meaningful progress, stop. Do not attempt a 4th fix. Return to the user with:

- What is failing and the exact error or finding
- What was attempted in each of the 3 attempts and why it didn't work
- Your assessment of why this is stuck (architectural mismatch, missing information, ambiguity in the plan)

## Constraints

- Follow the plan exactly. Do not add, remove, or restructure beyond what it specifies.
- Never batch all changes and test at the end. Each task must pass tests before the next begins.
- Do not modify files outside the plan's file map without flagging it to the user first.
