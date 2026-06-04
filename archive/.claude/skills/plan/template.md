# Plan: <Feature Name>

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** YYYY-MM-DD

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

| File | Responsibility | Public Interface |
|------|---------------|-----------------|
| `path/to/file` | One sentence — what this file owns and nothing else | What it exports or exposes |

### Modified Files

| File | What Changes | Why |
|------|-------------|-----|
| `path/to/file` | Specifically what is added, changed, or removed | Which requirement drives this |

### Deleted Files

| File | Why Deleted |
|------|------------|
| `path/to/file` | What it was replaced by or why it no longer belongs |

---

## Implementation Tasks

Tasks are ordered by dependency. Tests are written before implementation in every task.

---

### Task 1: <Name>

**Files:** `path/to/file`

**Tests:**

```
describe('<unit>', () => {
  it('<specific behavior> when <specific condition>')
  it('<specific behavior> when <specific condition>')
})
```

**Implementation:**

1. [Specific action — names the exact function, component, prop, route, or schema]
2. [Specific action]

**Commit:** `type: description`

---

### Task 2: <Name>

**Files:** `path/to/file`

**Tests:**

```
describe('<unit>', () => {
  it('<specific behavior> when <specific condition>')
})
```

**Implementation:**

1. [Specific action]

**Commit:** `type: description`

---

## Out of Scope

Anything explicitly excluded from this implementation. Documenting this prevents scope creep during implementation.

- Item and why it was excluded
