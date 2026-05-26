# Research: Remove unused `mcpServers: github` declarations from agents

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-05-22

## Summary

This research audits every agent file in `.claude/agents/` to determine which ones declare `mcpServers: - github` in their frontmatter, whether the agent body actually calls any `mcp__github__*` tool, and what the exact frontmatter edit must be for each affected file. The audit covers all 10 agent files. Findings confirm the spec exactly: 7 agents declare `mcpServers: - github`, 0 agents call any `mcp__github__*` tool, and `qa-reviewer.md` is the only agent where `mcpServers` survives the edit (it retains `- playwright`). The other 6 agents must have the entire `mcpServers:` key (header line + the `- github` list item) removed because the list would otherwise be empty.

## Codebase Areas Affected

- `.claude/agents/*.md` — the seven agent files listed in the per-file change list below. Only YAML frontmatter (between the `---` delimiters at the top of each file) is touched. Agent body prose, skills, model, and description fields remain untouched.

Out of scope (confirmed, no changes needed):

- `.claude/agents/onboard.md`, `.claude/agents/plan.md`, `.claude/agents/research.md` — none declare `mcpServers`. Already correct.
- `.mcp.json` — the spec's "Constraints" section explicitly forbids removing the `github` server entry from this file. Leave it alone.
- `.claude/skills/**` — explicitly out of scope per spec "Non-Goals".

## Reusable Code

This is a configuration-only change. Nothing to reuse from the codebase — the change is mechanical YAML editing of frontmatter blocks. The `Edit` tool with explicit `old_string` / `new_string` is the appropriate mechanism. No helper utility exists or is warranted.

## Gaps: What Needs to Be Created

Nothing new needs to be created. This is a pure removal change.

## Per-File Change List (Authoritative)

For each affected file, the table shows the current `mcpServers` block (with exact line numbers from the working tree on branch `feature/github-cli-in-agents` as of this research) and the exact frontmatter edit the Implement agent must apply.

> **Edit pattern (6 files): full-key removal.** When `mcpServers` lists only `- github`, the spec mandates removing the entire key (lines `mcpServers:` and `  - github`), not leaving an empty `mcpServers: []`. The frontmatter delimiters (`---`) stay put. No body content moves.
>
> **Edit pattern (1 file): list-item removal only.** `qa-reviewer.md` keeps `mcpServers:` with `- playwright` remaining. Only the `  - github` line is removed.

### 1. `.claude/agents/define.md`

- **Current frontmatter (lines 1–12):** has `skills: [agent-context, create-pr, git-commit, spec]` and `mcpServers: [github]` on lines 10–11.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** `git rev-parse`, `git checkout`, `git add`, `git commit`, `git push -u origin <branch>`, `gh pr create --draft …` — all via Bash. None require an MCP server.
- **Edit:** delete lines 10–11 (`mcpServers:` + `  - github`). After the edit, the line preceding `---` is `  - spec`. Resulting frontmatter has 10 lines.

### 2. `.claude/agents/implement.md`

- **Current frontmatter (lines 1–12):** has `skills: [agent-context, ui-design-brain, find-patterns, git-commit]` and `mcpServers: [github]` on lines 10–11.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** `git rev-parse --abbrev-ref HEAD`, `git rev-parse --abbrev-ref --symbolic-full-name @{u}`, `git pull`, `git checkout`, `git status --porcelain`, `git add`, `git commit`, `git push` — all via Bash.
- **Edit:** delete lines 10–11 (`mcpServers:` + `  - github`). Resulting frontmatter has 10 lines.

### 3. `.claude/agents/validate.md`

- **Current frontmatter (lines 1–10):** has `skills: [agent-context, git-commit]` and `mcpServers: [github]` on lines 8–9.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** `git rev-parse --abbrev-ref HEAD`, `git checkout`, `git symbolic-ref refs/remotes/origin/HEAD`, `git merge-base HEAD <base>`, `git diff …`, `git add`, `git commit`, `git push` — all via Bash.
- **Edit:** delete lines 8–9 (`mcpServers:` + `  - github`). Resulting frontmatter has 8 lines.

### 4. `.claude/agents/document.md`

- **Current frontmatter (lines 1–11):** has `skills: [agent-context, create-pr, git-commit]` and `mcpServers: [github]` on lines 9–10.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** `git rev-parse --abbrev-ref HEAD`, `git checkout`, `git symbolic-ref`, `git merge-base`, `git diff`, `git add`, `git commit`, `git push`, `gh pr edit`, `gh pr ready`, `gh repo view --json url -q .url` — all via Bash.
- **Edit:** delete lines 9–10 (`mcpServers:` + `  - github`). Resulting frontmatter has 9 lines.

### 5. `.claude/agents/code-reviewer.md`

- **Current frontmatter (lines 1–11):** has `skills: [agent-context, verify-correctness, verify-coherence]` and `mcpServers: [github]` on lines 9–10.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** `git rev-parse --abbrev-ref HEAD` and `git checkout <feature.branch>` (one-time branch sync at agent start). No `gh` calls. No commit, no push.
- **Edit:** delete lines 9–10 (`mcpServers:` + `  - github`). Resulting frontmatter has 9 lines.

### 6. `.claude/agents/senior-reviewer.md`

- **Current frontmatter (lines 1–13):** has `skills: [agent-context, verify-completeness, verify-correctness, verify-coherence, security-review]` and `mcpServers: [github]` on lines 11–12.
- **`mcp__github__*` calls in body:** none.
- **Other git/GitHub calls in body:** none. The body invokes skills (`/verify-completeness`, `/verify-correctness`, `/verify-coherence`, `/security-review`) and renders a verdict. No direct git or `gh` Bash calls anywhere.
- **Edit:** delete lines 11–12 (`mcpServers:` + `  - github`). Resulting frontmatter has 11 lines.

### 7. `.claude/agents/qa-reviewer.md` — partial removal

- **Current frontmatter (lines 1–11):** has `skills: [agent-context, verify-completeness]` and `mcpServers: [github, playwright]` on lines 8–10.
- **`mcp__github__*` calls in body:** none.
- **`mcp__playwright__*` calls in body:** none directly, but the spec keeps `playwright` because the QA evidence-capture flow ("Run the corresponding e2e test with screenshot or video capture enabled. Use whatever the project's e2e framework provides natively (Playwright `page.screenshot()` / video, Cypress `cy.screenshot()` / video, etc.)") implies access to the Playwright MCP server when the host project uses Playwright. Retention is mandated by spec Requirement #7 and Acceptance Criterion #7.
- **Other git/GitHub calls in body:** none.
- **Edit:** delete only line 9 (`  - github`). Keep line 8 (`mcpServers:`) and line 10 (`  - playwright`). After the edit, the `mcpServers` block reads:

  ```yaml
  mcpServers:
    - playwright
  ```

  Resulting frontmatter has 10 lines.

### Files explicitly unchanged

| File | `mcpServers` present? | Action |
| --- | --- | --- |
| `onboard.md` | No | none — already correct |
| `plan.md` | No | none — already correct |
| `research.md` | No | none — already correct |

## Verification of the Audit

The following commands and their outputs back this report:

1. **No `mcp__github__*` tool call exists in any agent body.**
   ```
   grep -n "mcp__github__" .claude/agents/*.md
   ```
   Result: empty (zero matches).

2. **No `mcp__*` tool call of any kind exists in any agent body.**
   ```
   grep -n "mcp__" .claude/agents/*.md
   ```
   Result: empty (zero matches). This means the only references to MCP servers in the entire agent corpus are the seven `mcpServers:` declarations themselves.

3. **Exactly seven `mcpServers:` blocks exist across all agents.**
   ```
   grep -nE "^mcpServers:" .claude/agents/*.md
   ```
   Result (sorted alphabetically by filename):
   - `code-reviewer.md:9`
   - `define.md:10`
   - `document.md:9`
   - `implement.md:10`
   - `qa-reviewer.md:8`
   - `senior-reviewer.md:11`
   - `validate.md:8`

   This matches the seven files named in the spec's Requirements section exactly.

4. **`github` MCP server is registered in `.mcp.json`.** The file's `mcpServers` key contains both `github` (via `@modelcontextprotocol/server-github`) and `playwright` (via `@playwright/mcp@latest`). The constraint to leave `.mcp.json` untouched is enforced by the spec.

## Patterns and Conventions to Follow

- **Per-step commit and push (project-wide).** `CLAUDE.md` mandates that every pipeline agent commits its own output (step doc + any artifacts + `context.yaml`) and pushes the feature branch before returning, using explicit file paths and `Skill(git-commit)`. The Implement agent for this feature follows the same rule — it will commit `.claude/agents/*.md` + `context.yaml` together.
- **Conventional Commits, no `Co-Authored-By`.** All commit messages in this repo use `type(scope): description`. The `git-commit` skill forbids AI attribution trailers. The Implement agent's commit should follow the form `refactor(agents): remove unused mcpServers github declarations` or similar.
- **`git add` with explicit paths only.** The project explicitly forbids `git add -A` and `git add .`. The Implement step must stage each modified agent file by name plus `context.yaml`.
- **Frontmatter delimiters always `---` on their own line.** All agents use a leading `---` on line 1 and a closing `---` after the YAML block. The edit must not disturb either delimiter.
- **Frontmatter key order observed across agents.** The conventional order is `name`, `description`, `model`, `skills:` (list), then `mcpServers:` (list, when present). Removing `mcpServers:` from the six full-removal files leaves `skills:` as the last key before the closing `---`. This matches `onboard.md`, `plan.md`, and `research.md`, which have always lacked `mcpServers`.

## Architectural Context

- **Why the dead declarations exist.** The Claude Code harness loads every server named in an agent's `mcpServers:` list before the agent starts running, regardless of whether the body actually calls any tool from that server. This is why the spec frames the removal as both a correctness fix (frontmatter should reflect real dependencies) and a startup-cost fix (avoid spinning up `@modelcontextprotocol/server-github` via `npx -y` on every invocation of these seven agents).
- **Interaction with the `github-tool-preference` skill.** That skill is listed in `system-reminder` skills and instructs Claude to prefer the `gh`/`git` CLI over the GitHub MCP server in every case. The seven agents listed above follow this guidance in their bodies (they only use the CLI). Their `mcpServers: - github` declarations are therefore unambiguously dead — there is no fallback path in any of the seven that ever reaches an MCP tool.
- **QA reviewer's Playwright dependency.** `qa-reviewer.md` does not call `mcp__playwright__*` tools by literal name in its prose either, but the spec keeps the declaration because the project's `.mcp.json` registers Playwright and the QA agent's evidence-capture instructions assume Playwright is available to the host project (the agent calls it via the project's own test runner, not by calling MCP tools directly). The agent declaration aligns with the project intent. Do not extend the audit to remove `playwright` from `qa-reviewer.md` — the spec is explicit that `playwright` remains.

## Key Insights for the Planner

- **The change is mechanical and parallel across 7 files.** Six edits remove two adjacent YAML lines (`mcpServers:` + `  - github`). One edit (`qa-reviewer.md`) removes just one YAML line (`  - github`). No other content moves. Treat the seven edits as one logical task — they share a single commit and a single rationale.
- **Each `Edit` tool call must include enough context to be unambiguous.** Because the two-line block `mcpServers:\n  - github\n` appears in six files, the Implement agent should include surrounding context (e.g. the preceding skill name and the trailing `---`) in each `old_string` so no edit accidentally hits the wrong file via partial-match heuristics. The per-file table above documents the exact preceding line for each edit.
- **Validation is grep-based and trivial.** After the edits, `grep -rn "mcpServers" .claude/agents/` must return exactly one line: `qa-reviewer.md:8:mcpServers:`. And `grep -nE "^  - github$" .claude/agents/*.md` must return zero matches. The Validate agent can verify acceptance criteria #1–#7 and #9 with these two commands alone.
- **No tests exist for agent frontmatter.** There are no unit or integration tests that parse `.claude/agents/*.md` frontmatter in this repo. Acceptance criterion #10 (frontmatter is valid YAML) is verified by visual inspection or by a one-off `python -c "import yaml; …"` check. The Implement agent does not need to add tests.
- **Branch already in correct state.** Working tree is clean. `git status` (start-of-session snapshot) reports `(clean)` and current branch is `feature/github-cli-in-agents`. No pre-edit branch hygiene is required.
- **Commit scope minimal and surgical.** The Implement commit should touch exactly: 7 agent files + `context.yaml` + (later) `3_plan.md`. No other paths.

## Artifacts

None. This research produces no reference files — the audit results are fully captured in the per-file change list above, which the Implement agent can read directly.

## Open Questions

- **Spec status discrepancy.** `1_spec.md` is marked `**Status:** Draft`, not `**Status:** Approved`. The `context.yaml` workflow shows `current_step: research` and `completed_steps: [define]`, indicating the orchestrator advanced the pipeline. Either the spec author intended to flip the status to Approved before handoff and missed it, or the Define step is marking specs complete without the explicit status flip. Either way, the spec content itself is unambiguous and the audit results match it exactly, so this does not block research. The Planner / Implement agent should not be blocked by this either, but the Document agent may want to note it as a process gap to address in the workflow tooling. The research and implementation proceed on the strength of the spec's content, not its status string.
