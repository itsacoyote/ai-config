---
name: efficiency-review
description: Use when you want a fast, read-only review of ONE task's recently-changed code for YAGNI, simplification, and clarity/naming — but not correctness, security, or test coverage. Scoped to the task diff, not the full branch. Ideal after an implementer agent finishes a single task, before committing or handing off.
allowed-tools: Read Bash(git diff *) Bash(git log *) Bash(git show *) Bash(find *) Bash(grep *)
---

# Efficiency Review

A read-only review of one task's changed code for **YAGNI, simplification, and clarity/naming**. This skill does **not** cover correctness, security, or test coverage — those belong to `senior-review`, `security-scan`, and `qa-review` respectively. Its value is speed: it catches over-engineering and naming drift early, before an expensive full review.

For the comprehensive engineering quality gate (correctness + coherence + YAGNI + security) see [`senior-review`](../senior-review/SKILL.md). `senior-review` links to the [criteria below](#simplification-and-yagni-criteria) for its YAGNI pass rather than restating them.

## When NOT to use

- Trivial diffs (a single-line fix, a config bump, a typo) — the overhead is not worth it.
- When you want a full branch review — `senior-review` scopes to the branch diff; this skill scopes to one task's chunk.

This skill can run alongside `senior-review`, `security-scan`, and `qa-review` at the validate step — they cover different dimensions and do not conflict.

## Scope

Review the **task diff** — the recently-changed code for a single task, not the full branch:

```bash
# Default: unstaged + staged changes (task in progress)
git diff HEAD

# Or, if the task was just committed, the last commit
git show HEAD
```

If the caller passes a specific file, path, or commit range, review that instead. Stay strictly within the passed scope — do not wander into unrelated files.

This is a narrower window than `senior-review`, which reviews the entire branch diff. That difference is intentional: this skill catches YAGNI and clarity issues while the task is still fresh and cheap to fix, not after an entire feature is built.

## The review pass

Run as a single named pass: **Simplification + YAGNI + Clarity/Naming**.

Work through the diff against the [criteria below](#simplification-and-yagni-criteria). For each finding, note severity, location, the problem, and the exact fix.

This is a read-only skill. Do not edit files, commit, or push — report findings and let the caller decide.

## Simplification and YAGNI Criteria

This is the canonical, detailed list. `senior-review` links here for its YAGNI pass.

### YAGNI (You Aren't Gonna Need It)

Flag anything built for hypothetical future requirements rather than the current task:

- **Unused parameters or options.** A function that accepts a config object where only one key is ever passed; optional parameters with no caller.
- **Abstraction with no second user.** An interface, base class, registry, factory, or plugin hook that has exactly one concrete implementation and no committed second use case. Three similar concrete cases first; abstract after the third.
- **Unreachable code paths.** Conditions that can never be true given the current callers, dead branches, early-return logic that makes later blocks unreachable.
- **Future-proofing flags.** A `version` field, `options.mode`, `strategy` enum, or similar that has only one valid value today and no committed roadmap item driving the others.
- **Over-generic naming or structure.** `EventBus`, `PluginManager`, `AbstractHandler` for code that does one specific thing with one caller. Name it what it does, not what it could theoretically become.

### Simplification

Flag unnecessary complexity in code that already works:

- **Could be fewer lines without losing clarity.** A five-line function that is really a one-liner; a loop that is a `map`/`filter`; nested conditions that flatten with an early return.
- **Abstraction not earning its complexity.** A helper function called once with no reuse; a utility module that wraps one standard-library call; a class where a plain function would do.
- **Middleware / pipeline for a single step.** An event emitter, observer chain, or middleware stack that has exactly one subscriber/handler. Use a direct function call.
- **Config-driven logic for a fixed set.** A config object that drives behavior for two or three cases that will never grow; a dynamic registry for a static list. Use explicit cases.
- **Redundant indirection.** A wrapper that does nothing but forward to the wrapped thing; an extra file/module boundary with no encapsulation benefit.

Check against [`incremental-implementation`](../incremental-implementation/SKILL.md) Rule 0 (Simplicity First):

> Would a staff engineer look at this and say "why didn't you just…"?  
> Am I building for hypothetical future requirements, or the current task?

### Clarity and Naming

Flag names that obscure intent:

- **Generic names with no domain meaning.** `data`, `handler`, `util`, `helper`, `manager`, `service` as a standalone name with no qualifier.
- **Misleading names.** A function named `getUser` that also mutates; a variable named `result` used for a list of items; a boolean named `flag`.
- **Inconsistent casing or style.** Mixed `camelCase` / `snake_case` in the same file; inconsistent naming patterns relative to the surrounding codebase (see `find-patterns` for conventions).
- **Abbreviations that save two characters.** `mgr`, `cfg`, `usr`, `idx` in non-loop contexts where the full word fits easily.
- **TypeScript-specific naming issues.** See [`.claude/rules/typescript-tips.md`](../../rules/typescript-tips.md) for: over-annotation that widens types, `any` instead of `unknown`, `as` casts that hide unsafe assumptions, enum names where literal unions would be clearer.

## Verdict

**If the diff is clean**, state:

> Efficiency review approved — [one to two sentences on what was reviewed and why it holds up].

**If there are findings**, list each one ordered by severity (highest first), formatted as:

- **Severity:** exactly one of `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO`
- **Where:** file, function/component, line if determinable
- **What:** the precise problem
- **Fix:** exactly what to change — not a suggestion, a prescription

Use the severity scale as follows for efficiency findings:

| Severity | Meaning |
|---|---|
| `HIGH` | Complexity that will actively hurt the next person to touch this code; a YAGNI abstraction that will mislead future contributors about intended scope |
| `MEDIUM` | Clear simplification opportunity or naming that obscures intent |
| `LOW` | Minor clarity improvement; a rename; a one-liner that's currently five lines |
| `INFO` | Observation worth noting but not worth blocking on |

`CRITICAL` is reserved for findings that indicate a fundamental structural problem worth stopping work for. Rare in a pure efficiency review; use it when the architecture choice will make correct behavior impossible or force a large rewrite later.

File an issue per unresolved finding linked to the feature task (see [`.claude/references/beads.md`](../../references/beads.md)).

## Non-negotiables

Do not approve code for efficiency reasons when a simplification would actually change behavior — that is a correctness concern, not an efficiency one; escalate to `senior-review`. Use the fixed severity vocabulary; do not invent labels.
