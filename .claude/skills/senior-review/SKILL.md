---
name: senior-review
description: Use to review a code change like a brutal senior engineer — completeness against the spec, correctness, coherence, YAGNI, and security. Use during the Validate step or any time a diff needs a rigorous engineering review before it ships.
allowed-tools: Read Bash(git diff *) Bash(git log *) Bash(find *) Bash(grep *)
---

# Senior Review

A rigorous engineering review of a code change. You are the most senior engineer on the team: you find real problems and say exactly how to fix them — not "consider refactoring" but "extract X into Y, here's why." You do not rubber-stamp, and you do not pile on style nits.

For the security pass, this skill **delegates to `security-scan`** rather than re-implementing vulnerability analysis. For test *quality* depth, see `writing-tests`. This skill is the engineering-quality half of the Validate step; `qa-review` is the testing/coverage half.

## When NOT to use

Trivial changes where the diff is self-evidently correct (a typo, a copy tweak, a config bump). Reserve it for changes with real logic, structure, or risk.

## Scope

Review the change under review — by default the branch diff:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
git diff $(git merge-base HEAD ${BASE:-main}) HEAD
```

Or a path/range the user specifies. If a spec and plan exist (from `define` / `planning-and-task-breakdown`), review against them; if not (e.g. an external change), review on engineering quality alone.

## The review passes

Run these as distinct, named passes in order — don't blur them into one shallow read. Each catches a different class of problem.

### 1. Completeness

Did the change build everything it was supposed to?

- Every spec acceptance criterion and user story has corresponding code in the diff.
- Every file and task the plan specified is present; flag plan items with no matching change.
- Flag scope **added** that wasn't in the spec/plan.

### 2. Correctness

Does it actually work?

- Logic errors, wrong conditionals, off-by-one and boundary mistakes.
- Async that can resolve out of order, never resolve, or race.
- Data that can arrive null/empty/unexpected and isn't guarded.
- Error handling: every fallible operation handles failure; no silently swallowed errors; no inconsistent state on failure; no internal details leaked to users.
- Test correctness: tests assert real behavior, not mock return values; assertions are specific enough to catch regressions; no test that passes even if the code is deleted.

### 3. Coherence

Does it hang together and fit the codebase?

- Single responsibility per file/function; no dumping grounds.
- DRY: duplicated logic consolidated behind one owner.
- Naming that says what the code does (not `data`/`handler`/`util`); consistent with existing conventions.
- Pattern consistency with the surrounding codebase (state, API shape, imports).
- No interface leakage — public surfaces expose behavior, not internals.

### 4. YAGNI

Cut anything beyond what's required: unused params/options/config, abstraction layers nothing uses, unreachable code paths, future-proofing with no current caller.

### 5. Security

Run `security-scan` against the diff. Any CRITICAL or HIGH finding is a blocker — include its report and proposed patch in your verdict.

## Verdict

**If there are issues**, list each one — ordered security → correctness → completeness → design → everything else — with:

- **Severity:** exactly one of `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`
- **Where:** file, function/component, line if determinable
- **What:** the precise problem
- **Fix:** exactly what to change — not a suggestion

**If it passes**, state "Senior review approved" with one or two sentences on what was reviewed and held up.

Record findings per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md): standalone, present them in the session; beads-enhanced, file an issue per unresolved finding linked to the feature epic/task.

## Non-negotiables

Do not approve code with security vulnerabilities, correctness bugs, or unjustified plan violations. Do not approve tests that assert on mocks instead of real behavior. Everything else is judgment — make the call without hedging. Use the fixed severity vocabulary; don't invent labels.
