---
name: edge-cases-and-risks
description: Use when researching or planning a feature to surface security-sensitive paths, domain rules that must be honored, non-obvious gotchas, and "this bites you if missed" hazards that should shape how the implementation is built.
argument-hint: "[feature area, module, or file-map slice]"
allowed-tools: Read Bash(find *) Bash(grep *)
---

# Edge Cases and Risks

Surface hazards, gotchas, and constraint violations that would bite an implementer who didn't know to look for them. This is a **research and awareness** step — it produces advisory heads-up notes, not tracked tasks or to-dos. Think of it as a developer flagging "watch out for X" before someone writes the code.

## When to Use

- Before implementing a feature, to front-load awareness of what could go wrong
- During planning, to inform design decisions with constraint awareness
- When reviewing a task breakdown, to identify gaps where risk wasn't considered
- When picking up an unfamiliar area of the codebase

**When NOT to use:** As a replacement for `security-and-hardening` (which is the implementation discipline itself), or for `security-scan` (which audits existing code for vulnerabilities). This skill is upstream of both — it's the research pass that generates awareness notes before a line is written, not the hardening rules you follow while writing or the scanner you run after. For routine changes with no new trust boundaries, domain rules, or external integrations, skip this and go straight to implementation.

## What to Surface

### Security-Sensitive Paths

Look for trust boundaries the feature will touch or introduce:

- User-supplied input that reaches storage, a query, or rendered output
- New authentication or authorization checks — or places where existing ones are bypassed
- New external service calls, webhooks, or file I/O
- Secrets, tokens, or credentials that will flow through the code

Flag these as "heads up: this path needs hardening." Don't prescribe the fix here — that's `security-and-hardening`.

### Business and Domain Rules That Must Be Honored

Grep and read for invariants the codebase already enforces:

- State machine constraints (e.g., an order can only be canceled before it ships)
- Data integrity rules enforced in the model layer or via DB constraints
- Billing, quota, or permission gates that other features respect
- Multi-tenancy boundaries — data that must never cross between tenants

Flag any of these that the new feature might silently violate. A rule that lives in one module but needs to be respected in a new one is exactly the kind of thing that gets missed.

### Non-Obvious Gotchas

Things that don't look dangerous on the surface but cause real pain:

- Race conditions — concurrent writes, double-submits, or time-of-check/time-of-use issues
- Ordering dependencies — code that assumes a specific call sequence
- Cache invalidation — data that gets cached and won't reflect a write without explicit eviction
- Timezone, locale, or encoding assumptions baked into existing logic
- Soft-delete patterns — queries that filter `deleted_at IS NULL` which new queries may forget
- ID type mismatches — numeric IDs vs. UUIDs, or mixed types in joins

### "This Bites You If Missed" Hazards

Failure modes that are easy to miss in code review but cause production incidents:

- Missing rollback or compensating logic for multi-step writes
- Cascading deletes or foreign-key constraints that trigger unexpectedly
- Background jobs or webhooks that assume data is still in a certain state when they run
- Pagination assumptions — code that fetches "all records" without a limit
- External API rate limits or retry behavior the calling code doesn't account for
- Silent truncation or coercion at a schema boundary (e.g., a string truncated to 255 chars)

### Decision-Affecting Concerns

Risks that should shape architectural choices, not just implementation details:

- A constraint that rules out an otherwise-obvious approach
- A data volume or frequency that makes a naive implementation unsafe at scale
- A regulatory or compliance requirement (data residency, retention, audit logging)
- An existing pattern that this feature should match — and what breaks if it diverges

## How to Look

Use `grep` and `find` to locate relevant code; use `Read` to understand it:

```bash
# Find existing validation or guard logic around the feature area
grep -r "validate\|guard\|authorize\|permission" src/path/to/area --include="*.ts" -l

# Find DB constraints, hooks, or callbacks that enforce invariants
grep -r "before_\|after_\|constraint\|unique\|foreign" --include="*.rb" -l

# Find soft-delete patterns
grep -r "deleted_at\|archived_at\|is_deleted" src/ --include="*.ts" -l

# Find existing rate-limit or quota checks
grep -r "rateLimit\|quota\|throttle" src/ --include="*.ts" -l
```

Read the code you find — don't just note the filename. The invariant is in the implementation, not the filename.

## What to Report

Write advisory awareness notes, not work items. Each note should read like a colleague flagging something before you start:

- **What the hazard is** — one sentence
- **Where it lives** — specific file or module
- **Why it matters for this feature** — what breaks or goes wrong if it's missed
- **Severity signal** — "must handle before shipping" vs. "worth knowing but low blast radius"

Keep it brief. The goal is to give the implementer a mental model of what to watch out for — not a second spec document. Notes that don't directly affect the feature being built belong in a separate backlog item, not here.

## What NOT to Report

- Generic best practices not specific to this feature (those live in `security-and-hardening`)
- Findings from existing code that predate this feature and aren't on the change path
- Hypothetical risks with no grounding in the actual codebase
- Tasks or action items — this output is awareness notes, not a to-do list

## See Also

- `security-and-hardening` — the implementation discipline for handling what this skill surfaces
- `security-scan` — audits existing or changed code for vulnerabilities after the fact
- `find-patterns` — identifies conventions and architecture before implementing; run this alongside edge-cases-and-risks during research
- `analyze-code` — surveys a module to understand what it does; useful when a hazard is flagged here and you need to understand it more deeply
