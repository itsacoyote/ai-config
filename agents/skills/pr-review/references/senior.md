# Senior Pass

Review the PR's diff for engineering quality: completeness, correctness, coherence, and
YAGNI. Security is a separate pass — skip it here. Find real problems and say exactly how to
fix them, not "consider refactoring."

## Completeness

Does the change build everything the PR claims? Every acceptance criterion or user story in
the description has corresponding code in the diff. Flag scope added that wasn't claimed, and
any claimed behavior with no matching change.

## Correctness

Does it actually work?

- Logic errors, wrong conditionals, off-by-one and boundary mistakes.
- Async that can resolve out of order, never resolve, or race.
- Data that can arrive null/empty/unexpected and isn't guarded.
- Error handling: every fallible operation handles failure; no silently swallowed errors; no
  internal details leaked to users.
- Test correctness: tests assert real behavior, not mock return values; no test that would
  still pass if the code under test were deleted.

## Coherence

Does it hang together and fit the codebase?

- Single responsibility per file/function; no dumping grounds.
- Duplicated logic consolidated behind one owner (DRY).
- Naming that says what the code does (not `data`/`handler`/`util`); consistent with the
  codebase's existing conventions.
- Pattern consistency with the surrounding code (state, API shape, imports).
- No interface leakage — public surfaces expose behavior, not internals.

## YAGNI

Cut anything beyond what's required: unused params/options/config, abstraction layers nothing
uses, unreachable code paths, future-proofing with no current caller.

## Finding format

Order correctness → completeness → coherence → YAGNI. For each:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:line
- **What** — the precise problem
- **Why** — the impact if left unfixed
- **Suggested comment text** — exactly what to change, ready to post as a review comment

If nothing is wrong, say so plainly: state what was reviewed and that it held up.
