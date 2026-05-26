# Spec: Remove unused `mcpServers: github` declarations from agents

**Date:** 2026-05-22  
**Status:** Draft

## Summary

Seven pipeline agents declare `mcpServers: - github` in their frontmatter, but none of them call any `mcp__github__*` tool in their body. All GitHub and git operations in these agents are performed via the `gh` CLI or `git` Bash commands. The declaration is dead configuration that loads an MCP server unnecessarily on every agent invocation. This spec covers auditing every agent file and removing the `github` entry from `mcpServers` in every agent that does not call an `mcp__github__*` tool.

## Problem Statement

Every `mcpServers` entry in agent frontmatter causes the Claude Code harness to spin up the named MCP server before the agent runs. When the agent never calls any tool from that server, the startup cost is wasted and the agent's declared capabilities misrepresent what it actually uses. The project's `github-tool-preference` skill explicitly states that CLI (`gh` / `git`) is always preferred over the GitHub MCP server, so agents that follow this guidance correctly end up with an `mcpServers: github` declaration they do not need. Any future reader of the frontmatter — human or agent — will incorrectly infer that the agent may call GitHub MCP tools, creating confusion about actual behavior and tool dependencies.

## Goals

- Every agent's `mcpServers` list accurately reflects only the MCP servers whose tools the agent's body actually calls.
- The `playwright` server remains declared on `qa-reviewer.md` because the QA reviewer uses Playwright for evidence capture.
- No agent loses access to any tool it actually uses.

## Non-Goals

- Adding `mcpServers: - github` to agents that currently lack it.
- Changing when or how agents use the `gh` CLI or `git` commands.
- Modifying any agent's behavior, prompts, or logic — only frontmatter declarations change.
- Auditing skills (`.claude/skills/`) — only agent files (`.claude/agents/`) are in scope.
- Adding the `github-tool-preference` skill to agent `skills:` lists (separate concern).

## User Stories

- As a developer reading an agent file, I want the `mcpServers` list to show only servers the agent actually uses, so that I can understand the agent's real dependencies at a glance without reading the full body.
- As the Claude Code harness, I want to avoid starting MCP servers that no tools in the running agent will call, so that agent startup is not burdened by unnecessary server processes.
- As a future agent author, I want to see consistent, accurate frontmatter in existing agents, so that I have a clear pattern to follow when writing my own.

## Requirements

- `define.md`: remove `mcpServers: - github`. The agent uses `gh pr create` via Bash; no `mcp__github__*` calls exist in the body.
- `implement.md`: remove `mcpServers: - github`. The agent uses `git push` / `git pull` via Bash; no `mcp__github__*` calls exist in the body.
- `validate.md`: remove `mcpServers: - github`. The agent uses `git push` / `git diff` via Bash; no `mcp__github__*` calls exist in the body.
- `document.md`: remove `mcpServers: - github`. The agent uses `gh pr edit`, `gh pr ready`, and `gh repo view` via Bash; no `mcp__github__*` calls exist in the body.
- `code-reviewer.md`: remove `mcpServers: - github`. The agent body contains pure review logic with no git or GitHub tool calls.
- `senior-reviewer.md`: remove `mcpServers: - github`. The agent body contains pure review logic with no git or GitHub tool calls.
- `qa-reviewer.md`: remove `mcpServers: - github` only. Retain `mcpServers: - playwright`. The agent uses Playwright for e2e test execution and screenshot/video capture; no `mcp__github__*` calls exist in the body.
- `onboard.md`, `plan.md`, `research.md`: no change required — they have no `mcpServers` declarations today.
- After all removals, every remaining `mcpServers` entry in every agent file corresponds to at least one `mcp__<server>__*` tool call in that agent's body, or is explicitly justified by a comment if the server is loaded for a conditional fallback path.

## Constraints

- The `github` MCP server must not be removed from `.mcp.json` — other non-agent contexts (e.g. the user running Claude Code interactively) may use it.
- Changes are limited to YAML frontmatter in `.claude/agents/*.md` files — no prose, logic, or skill declarations change.
- The `mcpServers` key must be removed entirely from an agent's frontmatter when the list would become empty after removing `github`; an empty `mcpServers: []` is valid YAML but misleading — prefer omitting the key.

## Acceptance Criteria

- [ ] `define.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `implement.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `validate.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `code-reviewer.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `senior-reviewer.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `document.md` frontmatter contains no `mcpServers` key (was `- github` only).
- [ ] `qa-reviewer.md` frontmatter contains `mcpServers: [playwright]` and no `github` entry.
- [ ] No agent body was modified — only frontmatter changed. (`git diff` shows only frontmatter lines removed.)
- [ ] `grep -r "mcpServers" .claude/agents/` returns only `qa-reviewer.md` with `playwright`.
- [ ] All nine agent files are syntactically valid YAML frontmatter (parseable between `---` delimiters).

## Open Questions

None. Scope and affected files are fully determined by audit.
