---
name: verify-correctness
description: Verify that the implementation actually does what it's supposed to do. Checks logic, error handling, edge cases, and that tests verify real behavior.
allowed-tools: Read Bash(git diff *) Bash(find *) Bash(grep *)
user-invocable: false
---

# Verify Correctness

Check that the implementation behaves correctly under the conditions the spec describes and the edge cases the code introduces.

## Current diff

```!
git diff main...HEAD
```

## What to check

**Logic correctness** — read the changed functions and components. Does the logic match what the spec and plan describe? Look for:

- Conditionals that branch incorrectly
- Off-by-one errors or boundary conditions handled wrong
- Async operations that could resolve out of order or not at all
- Data that could arrive in an unexpected shape and isn't guarded against

**Error handling** — every operation that can fail must handle failure explicitly. Look for:

- Network calls, file operations, or database queries with no error handling
- Errors caught and silently swallowed (empty catch blocks, caught-and-logged-but-not-propagated)
- Error states that leave the system in an inconsistent state
- User-facing errors that expose internal details

**Edge cases from the spec** — read the spec's constraints and acceptance criteria. Each constraint implies edge cases. Confirm the code handles them:

- Empty inputs, null values, zero quantities
- Maximum allowed values or lengths
- Unauthorized access attempts
- Concurrent or repeated operations

**Test correctness** — the tests prove the code works. Look for:

- Tests asserting on mock return values instead of real behavior — the system under test must be the real thing
- Tests that would pass even if the implementation were deleted or broken
- Assertions that are too broad to catch regressions (`expect(result).toBeTruthy()` instead of `expect(result).toBe(42)`)
- Missing assertions — tests that call the code but don't verify the output

## Output

List every correctness issue found:

- **Where:** file, function or component, line number if determinable
- **Problem:** what is wrong and what could go wrong as a result
- **Fix:** the specific change required

If no issues are found, state: "Correctness verified — logic, error handling, and test assertions look sound."
