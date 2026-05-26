# Plan: Remove unused `mcpServers: github` declarations from agents

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-05-22

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

None. This is a pure removal change.

### Modified Files

| File | What Changes | Why |
|------|-------------|-----|
| `.claude/agents/define.md` | Delete lines 10–11 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 12 to 10 lines. | Spec Requirement #1 — no `mcp__github__*` calls in body. |
| `.claude/agents/implement.md` | Delete lines 10–11 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 12 to 10 lines. | Spec Requirement #2 — no `mcp__github__*` calls in body. |
| `.claude/agents/validate.md` | Delete lines 8–9 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 10 to 8 lines. | Spec Requirement #3 — no `mcp__github__*` calls in body. |
| `.claude/agents/document.md` | Delete lines 9–10 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 11 to 9 lines. | Spec Requirement #4 — no `mcp__github__*` calls in body. |
| `.claude/agents/code-reviewer.md` | Delete lines 9–10 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 11 to 9 lines. | Spec Requirement #5 — no `mcp__github__*` calls in body. |
| `.claude/agents/senior-reviewer.md` | Delete lines 11–12 (`mcpServers:` header + `  - github` list item). Frontmatter shrinks from 13 to 11 lines. | Spec Requirement #6 — no `mcp__github__*` calls in body. |
| `.claude/agents/qa-reviewer.md` | Delete only line 9 (`  - github` list item). Keep line 8 (`mcpServers:`) and line 10 (`  - playwright`). Frontmatter shrinks from 11 to 10 lines. | Spec Requirement #7 — Playwright is retained for evidence capture; `github` is unused. |

### Deleted Files

None.

---

## Implementation Tasks

Tasks are ordered by file, alphabetical within the full-removal group, with the single partial-removal file last so the implementer doesn't mix patterns. The `Edit` tool's `old_string` must include enough surrounding context (the preceding skill name and the trailing `---` delimiter) to make the match unambiguous.

There are no automated tests for agent frontmatter in this repo (research finding §"Key Insights for the Planner"). Verification is grep-based and happens once in Task 8 after all edits are applied. Each per-file task lists the manual checks the implementer runs in the Read tool to confirm the edit landed correctly.

---

### Task 1: Remove `mcpServers: github` from `define.md`

**Files:** `.claude/agents/define.md`

**Tests:**

No automated tests exist for agent frontmatter. Post-edit manual verification:

```
Read .claude/agents/define.md lines 1-12
  asserts last frontmatter key is `skills:` with `  - spec` as its last item
  asserts line 10 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/define.md` with the Read tool to confirm current lines 8–12 match the expected pattern: `  - spec\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to the four-line block `  - spec\nmcpServers:\n  - github\n---` and `new_string` set to `  - spec\n---`. The leading two spaces on `  - spec` and `  - github` are part of the YAML list indentation and must be preserved exactly.
3. Re-read lines 1–12 of `.claude/agents/define.md` to confirm `skills:` now ends with `  - spec` immediately followed by the closing `---` delimiter on the next line.

**Commit:** No commit — all seven file edits land in a single commit in Task 8.

---

### Task 2: Remove `mcpServers: github` from `implement.md`

**Files:** `.claude/agents/implement.md`

**Tests:**

```
Read .claude/agents/implement.md lines 1-12
  asserts last frontmatter key is `skills:` with `  - git-commit` as its last item
  asserts line 10 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/implement.md` with the Read tool to confirm current lines 8–12 match `  - git-commit\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to `  - git-commit\nmcpServers:\n  - github\n---` and `new_string` set to `  - git-commit\n---`.
3. Re-read lines 1–12 to confirm `skills:` now ends with `  - git-commit` immediately followed by the closing `---`.

**Commit:** No commit — see Task 8.

---

### Task 3: Remove `mcpServers: github` from `validate.md`

**Files:** `.claude/agents/validate.md`

**Tests:**

```
Read .claude/agents/validate.md lines 1-10
  asserts last frontmatter key is `skills:` with `  - git-commit` as its last item
  asserts line 8 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/validate.md` with the Read tool to confirm current lines 6–10 match `  - git-commit\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to `  - git-commit\nmcpServers:\n  - github\n---` and `new_string` set to `  - git-commit\n---`.
3. Re-read lines 1–10 to confirm `skills:` now ends with `  - git-commit` immediately followed by the closing `---`.

**Commit:** No commit — see Task 8.

---

### Task 4: Remove `mcpServers: github` from `document.md`

**Files:** `.claude/agents/document.md`

**Tests:**

```
Read .claude/agents/document.md lines 1-11
  asserts last frontmatter key is `skills:` with `  - git-commit` as its last item
  asserts line 9 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/document.md` with the Read tool to confirm current lines 7–11 match `  - git-commit\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to `  - git-commit\nmcpServers:\n  - github\n---` and `new_string` set to `  - git-commit\n---`.
3. Re-read lines 1–11 to confirm `skills:` now ends with `  - git-commit` immediately followed by the closing `---`.

**Commit:** No commit — see Task 8.

---

### Task 5: Remove `mcpServers: github` from `code-reviewer.md`

**Files:** `.claude/agents/code-reviewer.md`

**Tests:**

```
Read .claude/agents/code-reviewer.md lines 1-11
  asserts last frontmatter key is `skills:` with `  - verify-coherence` as its last item
  asserts line 9 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/code-reviewer.md` with the Read tool to confirm current lines 7–11 match `  - verify-coherence\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to `  - verify-coherence\nmcpServers:\n  - github\n---` and `new_string` set to `  - verify-coherence\n---`.
3. Re-read lines 1–11 to confirm `skills:` now ends with `  - verify-coherence` immediately followed by the closing `---`.

**Commit:** No commit — see Task 8.

---

### Task 6: Remove `mcpServers: github` from `senior-reviewer.md`

**Files:** `.claude/agents/senior-reviewer.md`

**Tests:**

```
Read .claude/agents/senior-reviewer.md lines 1-13
  asserts last frontmatter key is `skills:` with `  - security-review` as its last item
  asserts line 11 is `---` (closing delimiter)
  asserts file contains no `mcpServers` token anywhere
```

**Implementation:**

1. Open `.claude/agents/senior-reviewer.md` with the Read tool to confirm current lines 9–13 match `  - security-review\nmcpServers:\n  - github\n---\n`.
2. Use the Edit tool with `old_string` set to `  - security-review\nmcpServers:\n  - github\n---` and `new_string` set to `  - security-review\n---`.
3. Re-read lines 1–13 to confirm `skills:` now ends with `  - security-review` immediately followed by the closing `---`.

**Commit:** No commit — see Task 8.

---

### Task 7: Remove only `  - github` list item from `qa-reviewer.md` (partial)

**Files:** `.claude/agents/qa-reviewer.md`

This task uses a different edit pattern than Tasks 1–6. `qa-reviewer.md` keeps the `mcpServers:` key and the `  - playwright` list item — only the `  - github` line is removed. Do not delete the `mcpServers:` header line.

**Tests:**

```
Read .claude/agents/qa-reviewer.md lines 1-11
  asserts line 8 is `mcpServers:`
  asserts line 9 is `  - playwright`
  asserts line 10 is `---` (closing delimiter)
  asserts file contains exactly one occurrence of `mcpServers`
  asserts file contains no occurrence of `- github`
```

**Implementation:**

1. Open `.claude/agents/qa-reviewer.md` with the Read tool to confirm current lines 8–11 match `mcpServers:\n  - github\n  - playwright\n---\n`.
2. Use the Edit tool with `old_string` set to `mcpServers:\n  - github\n  - playwright` and `new_string` set to `mcpServers:\n  - playwright`. Including both list items in the `old_string` makes the match unambiguous and guarantees the implementer does not accidentally delete the wrong line.
3. Re-read lines 1–11 to confirm the `mcpServers:` block now reads `mcpServers:\n  - playwright\n---`.

**Commit:** No commit — see Task 8.

---

### Task 8: Verify the audit, commit, and push

**Files:** all seven modified agent files plus `.docs/2026-05-22-github-cli-in-agents/context.yaml`.

**Tests:**

These three grep checks are the authoritative verification of acceptance criteria #1–#9. They replace the per-file Read checks in Tasks 1–7 with a single global pass.

```
Bash grep -rn "mcpServers" .claude/agents/
  asserts exactly one match: `.claude/agents/qa-reviewer.md:8:mcpServers:`

Bash grep -nE "^  - github$" .claude/agents/*.md
  asserts zero matches

Bash grep -n "mcp__github__" .claude/agents/*.md
  asserts zero matches (unchanged from pre-edit state — sanity check that no edit accidentally added a tool reference)
```

Additionally, run a one-off YAML parse check to satisfy acceptance criterion #10:

```
Bash python3 -c "import yaml, pathlib; \
  [yaml.safe_load(p.read_text().split('---',2)[1]) for p in pathlib.Path('.claude/agents').glob('*.md')]"
  asserts exit code 0 (every agent's frontmatter parses as valid YAML)
```

**Implementation:**

1. Run `grep -rn "mcpServers" .claude/agents/` and confirm the only line returned is `.claude/agents/qa-reviewer.md:8:mcpServers:`. If any other agent still contains `mcpServers`, revisit the corresponding task before proceeding.
2. Run `grep -nE "^  - github$" .claude/agents/*.md` and confirm zero matches.
3. Run `grep -n "mcp__github__" .claude/agents/*.md` and confirm zero matches (this should already have been zero before any edit — it confirms no edit slipped a stray reference in).
4. Run the YAML parse check above and confirm exit code 0.
5. Run `git diff --stat .claude/agents/` and confirm exactly seven files are listed with a net deletion (-13 lines total: 6 files × 2 lines + 1 file × 1 line). No additions outside the seven agent files.
6. Run `git status` and confirm the only untracked or modified paths are the seven agent files plus `.docs/2026-05-22-github-cli-in-agents/context.yaml` and `.docs/2026-05-22-github-cli-in-agents/4_validate.md` if Validate has not yet run (it will not have — Implement runs before Validate, so only the seven agents and `context.yaml` should be dirty at this point).
7. Invoke `Skill(git-commit)` to load the project's commit conventions.
8. Stage each modified file by explicit path — do not use `git add -A` or `git add .`:
   ```
   git add \
     .claude/agents/define.md \
     .claude/agents/implement.md \
     .claude/agents/validate.md \
     .claude/agents/document.md \
     .claude/agents/code-reviewer.md \
     .claude/agents/senior-reviewer.md \
     .claude/agents/qa-reviewer.md \
     .docs/2026-05-22-github-cli-in-agents/context.yaml
   ```
9. Commit with `git commit -m "refactor(agents): remove unused mcpServers github declarations"`. No body needed — the title is self-explanatory and the spec/research are linked from `context.yaml`. No `Co-Authored-By` trailer.
10. Push the branch with `git push`. If the push fails (non-zero exit), write `workflow.escalated: true` and the stderr to `context.yaml` per the project's push-failure escalation protocol and return without retrying.

**Commit:** `refactor(agents): remove unused mcpServers github declarations`

---

## Out of Scope

- **Adding `mcpServers: - github` to agents that currently lack it.** Explicit non-goal in the spec. `onboard.md`, `plan.md`, and `research.md` already have no `mcpServers` declaration and stay that way.
- **Removing `playwright` from `qa-reviewer.md`.** Spec Requirement #7 explicitly retains it for evidence capture.
- **Removing the `github` entry from `.mcp.json`.** Spec Constraints forbid this — the server remains available for interactive use outside agents.
- **Auditing `.claude/skills/**`.** Explicit non-goal — only agent frontmatter is in scope.
- **Adding `github-tool-preference` to any agent's `skills:` list.** Called out as a separate concern in the spec's Non-Goals.
- **Modifying any agent body content.** Acceptance criterion #8 mandates that `git diff` shows only frontmatter line removals.
- **Adding automated frontmatter validation tests.** Research §"Key Insights" confirms no such tests exist and none are needed — the grep + one-off YAML parse in Task 8 is sufficient.
