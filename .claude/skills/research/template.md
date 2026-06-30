# Research: <Feature Name>

**Spec/brief:** <link or short description, if any>
**Date:** YYYY-MM-DD

## Summary

One paragraph on the scope of this research and what areas of the codebase were examined.

## Codebase Areas Affected

List the directories, files, or modules that this feature will likely touch.

- `path/to/area` — reason it's relevant

## Reusable Code

### Endpoints

- `METHOD /path` — description of what it does and how it applies

### UI Components

- `ComponentName` (`path/to/file`) — what it does and how it can be used

### Utilities / Services / Other

- `functionOrClass` (`path/to/file`) — what it does and how it applies

## Gaps: What Needs to Be Created

- **New endpoint** — description and why existing ones don't cover it
- **New component** — description and why existing ones don't fit
- **Other** — anything else that must be built from scratch

## Patterns and Conventions to Follow

Document conventions observed in the codebase that the implementer should match.

- Convention or pattern — where it's used, why it matters for this feature

## Architectural Context

Anything about system design, integration points, or constraints that shapes how this feature should be built.

## Key Insights

Distilled observations that affect how this feature should be planned or built. Include anything that would affect sequencing, complexity, or approach — not risks (those go below).

- Insight 1
- Insight 2

## Risks & Gotchas

Edge cases, failure modes, and known traps the implementation plan must address. These are attached to the epic as advisory notes, not created as separate issues.

- Risk or gotcha — description and suggested mitigation

## Artifacts

- [`artifacts/filename`](artifacts/filename) — what it is and why it was created

## Open Questions

Anything discovered during research that may need a decision before the Planner can proceed.

- Question 1
