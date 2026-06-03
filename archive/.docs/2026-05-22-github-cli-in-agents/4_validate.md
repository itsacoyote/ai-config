# Validation: Audit agents and skills for git commands conflicting with github-tool-preference

**Date:** 2026-05-26
**Spec:** [1_spec.md](1_spec.md)

## Senior Code Review

**Verdict:** Approved
**Iterations:** 1

### Findings and fixes

No findings. The diff shows exactly 13 lines removed across 7 agent files — all deletions are within frontmatter blocks, zero body content was touched. The edit pattern is mechanically uniform and correct.

## QA Review

**Verdict:** Approved
**Coverage achieved:** 100%
**Iterations:** 1

### Findings and fixes

No findings. All 10 acceptance criteria verified by grep and structural inspection:

1. `define.md` frontmatter contains no `mcpServers` key — confirmed by grep returning no match for this file.
2. `implement.md` frontmatter contains no `mcpServers` key — confirmed.
3. `validate.md` frontmatter contains no `mcpServers` key — confirmed.
4. `code-reviewer.md` frontmatter contains no `mcpServers` key — confirmed.
5. `senior-reviewer.md` frontmatter contains no `mcpServers` key — confirmed.
6. `document.md` frontmatter contains no `mcpServers` key — confirmed.
7. `qa-reviewer.md` frontmatter contains `mcpServers: [playwright]` and no `github` entry — confirmed by reading lines 8–10 of the file.
8. No agent body was modified — confirmed by diff showing only `-mcpServers:` and `-  - github` lines removed; all body content is unchanged.
9. `grep -r "mcpServers" .claude/agents/` returns exactly one match: `qa-reviewer.md:8:mcpServers:` — confirmed.
10. All 9 agent files have valid YAML frontmatter — confirmed by structural parse: each file splits cleanly on `---` delimiters and yields a non-empty, well-formed frontmatter section.

### Verification commands and results

```
grep -rn "mcpServers" .claude/agents/
→ .claude/agents/qa-reviewer.md:8:mcpServers:
  (single result, as required)

grep -nE "^  - github$" .claude/agents/*.md
→ (no output — zero matches)

grep -n "mcp__github__" .claude/agents/*.md
→ (no output — zero matches)

git diff --stat .claude/agents/
→ 7 files changed, 0 insertions(+), 13 deletions(-)
   code-reviewer.md:  2 deletions
   define.md:         2 deletions
   document.md:       2 deletions
   implement.md:      2 deletions
   qa-reviewer.md:    1 deletion
   senior-reviewer.md: 2 deletions
   validate.md:       2 deletions
```

### Coherence check (verify-coherence)

All 7 changed files maintain the established frontmatter key order: `name` → `description` → `model` → `skills:` → (optionally) `mcpServers:` → `---`. After removal:
- 6 files end with `skills:` list immediately followed by `---`, matching the pattern of `onboard.md`, `plan.md`, and `research.md` which have always lacked `mcpServers`.
- `qa-reviewer.md` retains `mcpServers: [playwright]` between `skills:` and `---`, as mandated by the spec.

No naming inconsistencies, no structural drift, no DRY violations. The change is purely subtractive and internally consistent.

## Evidence

No `output_artifacts` were defined in `context.yaml` for this feature. The change is configuration-only (YAML frontmatter removal). Evidence is the set of grep commands above, all of which pass. The diff itself is the authoritative record.

| Artifact | Description | User story demonstrated |
|----------|-------------|------------------------|
| `git diff .claude/agents/` | 13-line net deletion across 7 frontmatter blocks, zero body changes | As a developer reading an agent file, the `mcpServers` list shows only servers the agent actually uses |
| `grep -rn "mcpServers" .claude/agents/` → one line | Only `qa-reviewer.md` retains `mcpServers` | As the Claude Code harness, no unnecessary MCP server processes are started for the 6 pipeline agents |
| All 9 agent frontmatter sections structurally valid | Consistent key-order across the entire agent corpus | As a future agent author, existing frontmatter provides a clear, accurate pattern to follow |
