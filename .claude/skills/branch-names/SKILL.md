---
name: branch-names
description: Use when creating, naming, or renaming a branch — before running git checkout -b / git switch -c to start any new work.
---

# Branch Names

Branch names are short but descriptive of the work to be done. Prefix with the
[Conventional Commits](https://www.conventionalcommits.org/) type that matches the
change, so the branch type lines up with the eventual commit and PR title.

## Format

```
<type>/<short-slug>
```

**Types** (same set used for commits and PR titles — see `git-commit` for what
each means): `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`, `ci`

**Slug rules:**

- Lowercase `kebab-case` — hyphens between words, no spaces or underscores
- Describe the work, not the ticket number alone (2–4 words is the sweet spot)
- A ticket ID may lead the slug when your workflow needs it: `fix/PROJ-123-token-refresh`

## Examples

```
feat/agent-model-assignments
fix/token-refresh
chore/remove-dead-code
refactor/auth-module
docs/setup-instructions
```

## Never use the type alone

NEVER create a branch named only by its type. `feat`, `fix`, and `chore` are not
branch names — they carry no information about the work.

## Common Mistakes

| Mistake | Fix |
|---|---|
| `feature/task-creation` | `feat/task-creation` (use the commit type `feat`, not `feature`) |
| `feat` | `feat/<short-slug>` (type alone is never a branch name) |
| `fix/Token_Refresh` | `fix/token-refresh` (lowercase, kebab-case) |
| `feat/fix-the-thing-that-was-broken-yesterday` | `fix/<short-slug>` (pick the right type, keep it short) |
| `my-branch` / `wip` | `<type>/<short-slug>` (always prefix with a type) |
