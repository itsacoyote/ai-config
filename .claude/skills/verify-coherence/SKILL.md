---
name: verify-coherence
description: Verify that the implementation is internally consistent and aligns with the codebase's established patterns. Checks design, naming, modularity, DRY, and plan conformance.
allowed-tools: Read Bash(git diff *) Bash(find *) Bash(grep *)
user-invocable: false
---

# Verify Coherence

Check that the implementation hangs together well and fits the codebase it was added to.

## Current diff

```!
git diff $(git merge-base HEAD main) HEAD
```

## What to check

**Plan conformance** — read `3_plan.md`'s file map. Each file has a stated single responsibility and a public interface. Check:

- Does each new or modified file do exactly what the plan said it would do, and nothing more?
- Does each file's public interface match what the plan specified?
- Did anything get added to a file that belongs in a different file per the plan?

**Single responsibility** — each file, component, function, and module should do one thing. Look for:

- Files that own multiple concerns (e.g., a component that fetches data, transforms it, and renders UI)
- Functions that do setup, business logic, and side effects in one body
- Modules that are a dumping ground for unrelated utilities

**DRY** — look for logic or structure duplicated across the diff. If the same pattern appears twice, it should be in one place with both callers depending on it. Flag duplication that wasn't in the plan as a design gap.

**Naming** — names should describe what the code does, not how it does it. Look for:

- Misleading names (a function called `getUser` that also mutates state)
- Generic names that provide no signal (`data`, `handler`, `util`, `helper` without qualification)
- Inconsistent naming relative to the rest of the codebase (check `2_research.md` for established conventions)

**Pattern consistency** — read `2_research.md`'s "Patterns and Conventions" section. The implementation should follow those patterns. Flag:

- Structural deviations (e.g., state managed locally when the pattern is global, or a new API shape that diverges from existing routes)
- Naming deviations from established conventions
- Import or dependency patterns that differ from the rest of the codebase without reason

**Interface leakage** — a module's public interface should expose behavior, not implementation. Look for:

- Internal types leaking through exported function signatures
- Callers that need to know how a module works internally to use it correctly
- Abstractions that are thinner than the implementation they wrap (exposing every internal knob)

**YAGNI** — anything in the diff that goes beyond the plan's scope:

- Unused parameters, options, or configuration fields
- Abstraction layers built for future extensibility that nothing currently uses
- Code paths that no caller can reach

## Output

List every coherence issue found:

- **Where:** file and function or component name
- **Problem:** what the design issue is and why it matters
- **Fix:** the specific structural change required

If no issues are found, state: "Coherence verified — structure, naming, and patterns are consistent with the plan and codebase."
