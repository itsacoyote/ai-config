---
name: create-pr
description: Use when creating a pull request, writing a commit message, or naming a branch. Covers conventional commits format for commits and PR titles, branch naming, and PR body structure.
---

# Creating Pull Requests

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`, `ci`

**Rules:**
- Lowercase, no trailing period
- Description is imperative mood ("add X", not "adds X" or "added X")
- Scope is optional but use it when the change is isolated to a clear area
- No `Co-Authored-By` trailers

**Examples:**
```
feat(agents): add model assignments to all agent frontmatter
fix(auth): handle expired token on refresh
docs: update setup instructions for new env vars
```

## PR Titles

Same format as commit messages — conventional commits style:

```
feat(scope): short description
```

The title should match or summarize the primary commit if it's a single-commit PR. For multi-commit PRs, write a title that captures the overall change.

## Branch Names

```
<type>/<short-slug>
```

Examples: `feat/agent-model-assignments`, `fix/token-refresh`, `chore/remove-dead-code`

## PR Body

```markdown
## Summary
- What changed and why (2-4 bullets)

## Test plan
- How to verify the change works
```

Keep it tight. The commit messages carry the detail; the PR body orients the reviewer.
