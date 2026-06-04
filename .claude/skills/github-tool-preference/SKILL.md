---
name: github-tool-preference
description: Defines the preferred tool order for all git and GitHub operations. Always use GitHub CLI (gh / git) first; fall back to the GitHub MCP server only when CLI cannot complete the task.
---

# GitHub Tool Preference

## Rule

**Always reach for the GitHub CLI first.** Use `gh` and `git` Bash commands for every git and GitHub operation. Only fall back to the `mcp__github__*` tools when the CLI cannot complete the task.

## When to use CLI (default)

Use `gh` / `git` via Bash for:

- Creating, viewing, listing, updating, or merging pull requests (`gh pr create`, `gh pr list`, `gh pr view`, etc.)
- Creating or viewing issues (`gh issue create`, `gh issue view`, etc.)
- Pushing, pulling, cloning, branching, committing (`git push`, `git pull`, etc.)
- Checking CI status (`gh pr checks`, `gh run list`)
- Commenting on PRs or issues (`gh pr comment`, `gh issue comment`)
- Any operation where a `gh` subcommand exists

## When to fall back to the GitHub MCP

Use `mcp__github__*` tools only when:

- The `gh` CLI is not available or not authenticated in the current environment
- The operation requires a GitHub API capability that `gh` does not expose (e.g. creating a repository via API with specific settings the CLI flag doesn't support)
- A `gh` command fails with an auth or network error that cannot be resolved

When falling back, note why the CLI could not be used.

## Never mix tools for the same operation

Do not call `gh pr create` and then `mcp__github__create_pull_request` for the same PR. Pick one path and use it end-to-end.

## Quick reference

| Task | Preferred | Fallback |
|---|---|---|
| Create PR | `gh pr create` | `mcp__github__create_pull_request` |
| List PRs | `gh pr list` | `mcp__github__list_pull_requests` |
| View PR | `gh pr view` | `mcp__github__get_pull_request` |
| Comment on PR | `gh pr comment` | `mcp__github__add_issue_comment` |
| Create issue | `gh issue create` | `mcp__github__create_issue` |
| Push branch | `git push` | `mcp__github__push_files` |
| Get file | `cat` / Read tool | `mcp__github__get_file_contents` |
