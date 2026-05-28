# Plan: Context compaction handoff

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-05-27

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

This feature is documentation-only — every file in scope is a markdown instruction document for a Claude Code agent/skill or a YAML template. There is no application code, no test suite, and no new file is created. All work is additive edits to nine existing files.

### New Files

None. This feature does not create any new files.

### Modified Files

| File | What Changes | Why |
|------|-------------|-----|
| `.claude/skills/agent-context/template.yaml` | Add `summary: ""` as the last field of the `workflow:` block, with a one-line inline comment plus a multi-line YAML example in a comment block underneath showing the three required content areas (accomplished / findings & decisions / relevant context for next phase). | Spec Acceptance Criterion #1 — `workflow.summary` field must exist in the template with a default of `""` and an inline-comment description. Research §"Gaps" + §"Patterns and Conventions to Follow" (last in `workflow` block, with shape example because one-line comment cannot convey three content areas). |
| `.claude/skills/agent-context/SKILL.md` | Insert a new `## Workflow summary` section between `## Resuming a disrupted workflow` and `## Artifacts registry`. Section documents purpose (primary handoff narrative enabling progressive context loading), shape (prose, 300–500 tokens), three required content areas, lifecycle (overwrite per step), who writes it (every pipeline agent before returning), who reads it (next agent on start; orchestrator for orientation). Use the same structure as the existing registry sections: heading + purpose paragraph + YAML example + lifecycle note. | Spec Acceptance Criterion #7 — `agent-context/SKILL.md` must document the `workflow.summary` field. Research §"Gaps" + §"Patterns and Conventions to Follow" (placement between Resuming and Artifacts; mirror registry-section structure). |
| `.claude/skills/feature/SKILL.md` | Append a new step 8 to the **Post-return protocol**: invoke `/compact` (bare, no arguments) after `git push` succeeds. Include an explicit prose note that `/compact` is not run when the protocol halted at step 2 on `workflow.escalated: true`, so the escalation conversation stays intact for the user. | Spec Acceptance Criteria #5 and #6 — orchestrator runs `/compact` after push on every non-escalation transition, and the no-compact-on-escalation contract is explicit. Research §"Architectural Context" (`/compact` is a built-in bare command) and §"Key Insights" (structural placement after step 2's escalation halt satisfies the requirement; explicit prose note documents intent). |
| `.claude/agents/define.md` | Insert a new numbered step in `## After the workflow completes`, between the existing step 1 ("write `1_spec.md`") and step 2 ("commit the spec and `context.yaml`"). The new step overwrites `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas. Renumber subsequent steps. **No gate change** — Define is the first step and has no prior summary to read. | Spec Acceptance Criteria #2, #3 — summary write before the commit so it lands in the same commit as `1_spec.md` (per spec Requirement: same commit as step doc). Research §"Key Insights" — Define is the asymmetric agent; only gets the write, not the read. |
| `.claude/agents/research.md` | Two edits. (a) In `## Gate`, insert a new bullet before "Read `1_spec.md` fully before proceeding" directing the agent to read `workflow.summary` from `context.yaml` first as the primary handoff narrative, with prior step docs read on demand only. Plus a one-sentence instruction that the agent's opening message acknowledge it has read the summary (auditability per spec Acceptance Criterion #8 and Research open-question #3). (b) In `## After the workflow completes`, insert a new numbered step between the existing step 2 ("save artifacts") and step 3 ("commit"). The new step overwrites `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas. Renumber subsequent steps. | Spec Acceptance Criteria #2, #3, #4, #8. Research §"Key Insights" — gate-read line is a single bullet matching the file's existing bullet style; summary write before commit so it lands in the same commit as `2_research.md`. |
| `.claude/agents/plan.md` | Same shape as Research. (a) Gate bullet directing the agent to read `workflow.summary` first (slotted before "Read `1_spec.md` and `2_research.md` fully"), plus opening-message acknowledgment instruction. (b) New numbered step in `## After the workflow completes` between the existing step 2 (`recommended_skills` scan) and step 3 (commit). Renumber subsequent steps. | Same as Research. |
| `.claude/agents/implement.md` | Two edits. (a) In `## Gate`, insert a new bullet directing the agent to read `workflow.summary` first as the primary handoff narrative (this file uses bullets; match style), plus opening-message acknowledgment instruction. Place before "Read `1_spec.md` and `3_plan.md` fully" so the summary is read before the spec/plan re-loads (which become on-demand). (b) In `## After all tasks complete`, insert a new numbered step **before** the existing step 1 (the `git status --porcelain` check). The new step overwrites `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas. Renumber subsequent steps so the porcelain check becomes step 2 and the push becomes step 3. | Spec Acceptance Criteria #2, #3, #4, #8. Research §"Key Insights" — Implement's after-section is non-standard; the summary write belongs in "After all tasks complete" before the porcelain check so the summary update is captured in whatever final commit lands. |
| `.claude/agents/validate.md` | Two edits. (a) In `## Gate` (numbered list), insert a new numbered item directing the agent to read `workflow.summary` first as the primary handoff narrative, plus opening-message acknowledgment instruction. Place between the existing step 4 (diff check) and step 5 ("Read `1_spec.md`, `2_research.md`, and `3_plan.md` fully"). Renumber step 5 to step 6. (b) In `## After the workflow completes`, insert an explicit instruction *before* the existing `git add ... git commit` block, directing the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas. | Spec Acceptance Criteria #2, #3, #4, #8. Research §"Reusable Code" — Validate's gate uses a numbered list (not bullets); match. Summary write before the commit so it lands in the same commit as `4_validate.md`. |
| `.claude/agents/document.md` | Two edits. (a) In `## Gate` (numbered list), insert a new numbered item directing the agent to read `workflow.summary` first as the primary handoff narrative, plus opening-message acknowledgment instruction. Place between the existing step 4 (read full diff) and step 5 (read `1_spec.md`). Renumber step 5 to step 6. (b) In `## Commit and push documentation`, insert an explicit instruction *before* the existing `git add ... git commit` example, directing the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas. | Spec Acceptance Criteria #2, #3, #4, #8. Research §"Key Insights" — Document's closing section is `## Commit and push documentation`, not "After the workflow completes"; the summary write belongs in that section before the commit. |

### Deleted Files

None.

---

## Implementation Tasks

Tasks are ordered by dependency. The template task (Task 1) ships first so the field declaration is visible before any agent writes to it. The orchestrator and skill-doc updates (Tasks 2–3) ship next so the post-return protocol and the documentation of the field land together. Agent edits (Tasks 4–9) ship one file per task — they are independent of each other and can land in any order after the template, but a stable per-file commit cadence keeps the diff easy to review and easy to revert.

Each task ends with a single conventional commit. Because this feature does not produce per-task tests (the repo has no test suite and the files are documentation), each task's verification is a manual acceptance check listed in place of `describe(...) / it(...)` blocks. The Validate step exercises the end-to-end dry run.

**Cross-task constraint to remember.** The agent files (Tasks 4–9) all use the same gate-read bullet wording, the same after-section write wording, and the same opening-message acknowledgment instruction. The wording is fixed once in Task 4 (Define has no gate-read, so wording is fixed for the after-section write in Task 4 and for the gate-read in Task 5) and reused verbatim in subsequent tasks. Re-deriving the wording per task would violate DRY and risk drift. The exact wording is captured in the **Shared wording reference** section at the bottom of this plan.

---

### Task 1: Add `workflow.summary` to the `context.yaml` template

**Files:** `.claude/skills/agent-context/template.yaml`

**Acceptance:**

```
template.yaml
  - `summary: ""` appears as the last field in the `workflow:` block, after `escalation_reason`
  - inline comment on the same line as `summary: ""` describes it as the primary handoff narrative for progressive context loading
  - a multi-line YAML comment block immediately underneath the `summary` line shows an example block scalar covering the three required content areas (accomplished / findings & decisions / relevant context for next phase)
  - example block scalar is trimmed (≤ ~15 lines) — not a verbatim copy of the in-flight feature's full summary
  - no other field in the `workflow:` block is renamed, removed, or reordered
  - file remains valid YAML when parsed (no tab characters, consistent indentation, comments do not break parsers)
```

**Implementation:**

1. Open `.claude/skills/agent-context/template.yaml`.
2. After the `escalation_reason: ""` line (currently the last field in the `workflow:` block), append:
   ```yaml
     summary: ""          # Outcome-focused prose summary of the most recent completed step. Overwritten per step. Primary handoff narrative for the next agent — enables progressive context loading.
   ```
3. Immediately under that line, add a YAML comment block showing a trimmed example of a well-formed summary, derived from the in-flight `.docs/2026-05-27-context-compaction-handoff/context.yaml`. The example should illustrate the three required content areas with clear paragraph breaks or section markers. Keep it ≤ ~15 lines so the template doesn't bloat.
4. Verify the file still parses cleanly: run `python3 -c "import yaml; yaml.safe_load(open('.claude/skills/agent-context/template.yaml'))"`.

**Commit:** `feat(agent-context): add workflow.summary field to context.yaml template`

---

### Task 2: Document `workflow.summary` in the `agent-context` skill

**Files:** `.claude/skills/agent-context/SKILL.md`

**Acceptance:**

```
agent-context/SKILL.md
  - a new `## Workflow summary` H2 section exists
  - the section sits between `## Resuming a disrupted workflow` and `## Artifacts registry`
  - the section's structure mirrors the existing registry sections (purpose paragraph → YAML example → lifecycle note)
  - the section names: (a) purpose — primary handoff narrative enabling progressive context loading, (b) shape — prose, 300–500 tokens, (c) three required content areas — what was accomplished, key findings and decisions, relevant context for the next phase, (d) lifecycle — overwritten by each agent before returning, (e) who writes — every pipeline agent (Define through Document), (f) who reads — next agent on start as its primary context source; orchestrator for orientation
  - escalation interaction is mentioned: an agent that escalates may write a partial-progress summary, but the orchestrator does not run /compact on an escalation halt
  - no existing section is renamed, removed, or restructured
```

**Implementation:**

1. Open `.claude/skills/agent-context/SKILL.md`.
2. Locate the `## Resuming a disrupted workflow` section. Immediately after the **Step-specific resume notes** bullet block ends, before the `## Artifacts registry` heading, insert a new `## Workflow summary` H2 section.
3. Write the section using this structure (purpose paragraph → YAML example → lifecycle note), matching the voice of the surrounding registry sections:
   - **Purpose paragraph:** Explain that `workflow.summary` is the outcome-focused prose summary written by each pipeline agent before returning, and that it is the primary handoff narrative for the next agent. State the goal: progressive context loading — the next agent reads the summary first and only opens prior step docs on demand when a specific detail is needed.
   - **Shape and content paragraph:** Specify prose (not bullets or YAML), 300–500 token target, and the three required content areas in order: (1) what the step accomplished, (2) key findings and decisions, (3) relevant context for the next phase. Note that the summary lives as a YAML block scalar (`|`) under `workflow.summary` for parser-clean multi-line content.
   - **YAML example block:** Show a trimmed `workflow:` snippet illustrating `summary: |` followed by a few representative lines of prose. Keep ≤ ~12 lines.
   - **Lifecycle note:** Written by every pipeline agent (Define through Document) immediately before returning. Overwritten per step — only the most recent completed step's summary lives in the field. Read by the next agent on start as its primary context source. Also useful to the orchestrator for orientation and to a developer resuming the workflow.
   - **Escalation note:** Final sentence — an agent that escalates may write a partial-progress summary, but the orchestrator does not run `/compact` on an escalation halt, so the conversation remains intact for the user to inspect.
4. Save and visually confirm the heading depth (`##`) matches the surrounding sections, and that the section reads in the same imperative voice as the rest of the doc.

**Commit:** `docs(agent-context): document workflow.summary field`

---

### Task 3: Add `/compact` to the orchestrator's post-return protocol

**Files:** `.claude/skills/feature/SKILL.md`

**Acceptance:**

```
feature/SKILL.md
  - a new step 8 is appended to the Post-return protocol after step 7 (`git push`)
  - step 8 invokes `/compact` (bare — no focus instructions) to compact the orchestrator's conversation history
  - step 8 includes an explicit prose note that /compact is NOT run when the protocol halted at step 2 on `workflow.escalated: true` — the escalation conversation must stay intact
  - the note explains that structurally, step 2's halt occurs before step 8 is reached, but documents intent so future readers understand the contract
  - no existing post-return-protocol step is renamed, removed, or renumbered
  - the Approval Gate and Step sequence sections are unchanged
```

**Implementation:**

1. Open `.claude/skills/feature/SKILL.md`.
2. Locate the **Post-return protocol** subsection. After the existing step 7 (the `git push` step with the in-line escalation handling), append a new numbered step 8:
   ```text
   8. Invoke `/compact` to summarize the orchestrator's conversation history so far. Run this on every successful step transition. Do not run `/compact` when the post-return protocol halted at step 2 (`workflow.escalated: true`) — the escalation halt occurs before this step is reached, so the escalation conversation stays intact for the user to inspect. This is structurally enforced, but documented here so the contract is explicit.
   ```
3. Verify the post-return-protocol numbered list is now 1–8 with no gaps.
4. Do not touch the Approval Gate, Step sequence, or Completion subsections.

**Commit:** `feat(feature): run /compact after every non-escalation step transition`

---

### Task 4: Add summary-write step to the Define agent

**Files:** `.claude/agents/define.md`

**Acceptance:**

```
define.md
  - a new numbered step is inserted in `## After the workflow completes`, between existing step 1 (write `1_spec.md`) and existing step 2 (commit)
  - the new step instructs the agent to overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary
  - the instruction specifies the three required content areas: (1) what was accomplished, (2) key findings and decisions, (3) relevant context for the next phase (Research)
  - the instruction clarifies the summary is prose (not bullets), overwritten (not appended), and self-contained so the next agent can start from it alone
  - subsequent steps in the section are renumbered (old 2→3, 3→4, 4→5, 5→6)
  - no other section of define.md is modified — in particular, the Gate section is unchanged
  - existing commit message wording (`docs(spec): add spec for ...`) is unchanged
```

**Implementation:**

1. Open `.claude/agents/define.md`.
2. Locate `## After the workflow completes`. The current list runs 1–5 (write spec → commit → push → gh pr create → return).
3. Insert a new step between the existing step 1 and step 2. Use the shared **Summary write instruction** wording from the Shared wording reference at the bottom of this plan, substituting `<next agent>` with "Research" and `<this step doc>` with "`1_spec.md`":
   ```text
   2. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Research) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Define accomplished, (2) key findings and decisions made during discovery (including why, when non-obvious), (3) relevant context for the Research phase — scope boundaries, anything from the conversation that shaped `1_spec.md` but isn't self-evident from the spec itself.
   ```
4. Renumber the previously-existing steps 2, 3, 4, 5 to 3, 4, 5, 6.
5. Do not change the Gate, Workflow, or Push-failure escalation sections.

**Commit:** `feat(define): write workflow.summary before commit and push`

---

### Task 5: Add gate-read and summary-write to the Research agent

**Files:** `.claude/agents/research.md`

**Acceptance:**

```
research.md
  - Gate section: a new bullet is inserted before "Read `1_spec.md` fully before proceeding"
  - the new bullet directs the agent to read `workflow.summary` from context.yaml first as the primary handoff narrative
  - the bullet states prior step docs (1_spec.md, etc.) are read on demand only when a specific detail is needed beyond what the summary carries
  - the bullet includes a one-sentence instruction that the agent's opening message acknowledge it has read the summary (e.g. "Per `workflow.summary`, Define ...")
  - After-workflow section: a new numbered step is inserted between existing step 2 (save artifacts) and existing step 3 (commit)
  - the new step instructs the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas, with next-phase context aimed at Plan
  - subsequent steps are renumbered (old 3→4, 4→5)
  - no other section of research.md is modified — Workflow and Push-failure escalation sections unchanged
  - existing commit message wording (`docs(research): add research for ...`) is unchanged
```

**Implementation:**

1. Open `.claude/agents/research.md`.
2. **Gate edit.** Locate the Gate bullet list. Insert a new bullet before the existing "Read `1_spec.md` fully before proceeding" bullet. Use the shared **Gate-read bullet** wording from the Shared wording reference, with `<this step>` substituted with "Research" and the prior-step doc list as "`1_spec.md`":
   ```text
   - Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, etc.) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Define produced …") so the read is auditable.
   ```
3. **After-workflow edit.** Locate `## After the workflow completes`. The current list runs 1–4 (write research → save artifacts → commit → push). Insert a new step between the existing step 2 and step 3. Use the shared **Summary write instruction** wording, substituting `<next agent>` with "Plan" and `<this step doc>` with "`2_research.md`":
   ```text
   3. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Plan) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Research accomplished, (2) key findings and decisions made during research (including why, when non-obvious), (3) relevant context for the Plan phase — patterns to follow, gaps, scope boundaries, and anything that shaped `2_research.md` but isn't self-evident from the doc itself.
   ```
4. Renumber the previously-existing steps 3, 4 to 4, 5.
5. Do not change the Workflow or Push-failure escalation sections.

**Commit:** `feat(research): read workflow.summary on entry, write it before commit`

---

### Task 6: Add gate-read and summary-write to the Plan agent

**Files:** `.claude/agents/plan.md`

**Acceptance:**

```
plan.md
  - Gate section: a new bullet is inserted before "Read `1_spec.md` and `2_research.md` fully"
  - the new bullet uses the same wording shape as Research's gate-read bullet, substituting "Plan" and the prior-step doc list as "`1_spec.md`, `2_research.md`"
  - includes the opening-message acknowledgment instruction
  - After-workflow section: a new numbered step is inserted between existing step 2 (recommended_skills scan) and existing step 3 (commit)
  - the new step instructs the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas, with next-phase context aimed at Implement
  - subsequent steps are renumbered (old 3→4, 4→5)
  - no other section of plan.md is modified
  - existing commit message wording (`docs(plan): add implementation plan for ...`) is unchanged
```

**Implementation:**

1. Open `.claude/agents/plan.md`.
2. **Gate edit.** Insert a new bullet before "Read `1_spec.md` and `2_research.md` fully…" using the shared **Gate-read bullet** wording with prior-step doc list "`1_spec.md`, `2_research.md`":
   ```text
   - Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, `2_research.md`, etc.) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Research produced …") so the read is auditable.
   ```
3. **After-workflow edit.** Insert a new step between the existing step 2 (`recommended_skills` scan) and step 3 (commit). Use the shared **Summary write instruction** wording with `<next agent>` = "Implement" and `<this step doc>` = "`3_plan.md`":
   ```text
   3. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Implement) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Plan accomplished, (2) key findings and decisions about decomposition and task ordering, (3) relevant context for the Implement phase — DRY/YAGNI calls, the file map's intent, any task ordering rationale that isn't self-evident from `3_plan.md` itself.
   ```
4. Renumber the previously-existing steps 3, 4 to 4, 5.
5. Do not change the Workflow or Push-failure escalation sections.

**Commit:** `feat(plan): read workflow.summary on entry, write it before commit`

---

### Task 7: Add gate-read and summary-write to the Implement agent

**Files:** `.claude/agents/implement.md`

**Acceptance:**

```
implement.md
  - Gate section: a new bullet is inserted before "Read `1_spec.md` and `3_plan.md` fully"
  - the new bullet uses the same wording shape as Research/Plan's gate-read bullet, substituting "Implement" and prior-step doc list "`1_spec.md`, `3_plan.md`"
  - includes the opening-message acknowledgment instruction
  - After-all-tasks-complete section: a new numbered step is inserted BEFORE the existing step 1 (the `git status --porcelain` check)
  - the new step instructs the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas, with next-phase context aimed at Validate
  - subsequent steps are renumbered (old 1→2 — porcelain check, old 2→3 — push)
  - the After-each-task-completes section is unchanged (checkpoint behavior unchanged)
  - no other section of implement.md is modified
```

**Implementation:**

1. Open `.claude/agents/implement.md`.
2. **Gate edit.** Locate the Gate bullet list. Insert a new bullet before "Read `1_spec.md` and `3_plan.md` fully…":
   ```text
   - Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, `3_plan.md`, etc.) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Plan produced …") so the read is auditable.
   ```
3. **After-all-tasks-complete edit.** Locate `## After all tasks complete`. The current list has 2 steps (porcelain check → push). Insert a new step *before* step 1, using the shared **Summary write instruction** wording with `<next agent>` = "Validate" and `<this step doc>` = "the implementation diff":
   ```text
   1. Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Validate) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Implement accomplished (what was built, how many tasks landed, the high-level shape of the diff), (2) key findings and decisions made during implementation (deviations from the plan, surprises, anything resolved on the fly), (3) relevant context for the Validate phase — known weak spots, areas of the diff that warrant extra senior-review attention, test-coverage gaps, anything that isn't self-evident from the diff itself.
   ```
4. Renumber the previously-existing steps 1, 2 to 2, 3. Step 2 becomes the porcelain check; step 3 becomes the push. Note that the porcelain check now naturally covers the freshly-written `workflow.summary` change to `context.yaml`, so the existing "commit `context.yaml`" path in step 2 ensures the summary lands in a commit before the push.
5. Do not change the Workflow, After-each-task-completes, Push-failure escalation, or "If the skill cannot complete" sections.

**Commit:** `feat(implement): read workflow.summary on entry, write it before final push`

---

### Task 8: Add gate-read and summary-write to the Validate agent

**Files:** `.claude/agents/validate.md`

**Acceptance:**

```
validate.md
  - Gate section: Validate uses a numbered list, not bullets. A new numbered item is inserted between existing step 4 (diff check) and existing step 5 (read `1_spec.md`, `2_research.md`, `3_plan.md` fully)
  - the new item directs the agent to read `workflow.summary` first as the primary handoff narrative, with prior step docs read on demand only, and includes the opening-message acknowledgment instruction
  - existing step 5 is renumbered to step 6
  - After-workflow section: an explicit instruction is inserted BEFORE the `git add ... git commit` block
  - the instruction directs the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas, with next-phase context aimed at Document
  - no other section of validate.md is modified — escalation sections unchanged
  - existing commit message wording (`docs(validate): add validation report for ...`) is unchanged
```

**Implementation:**

1. Open `.claude/agents/validate.md`.
2. **Gate edit.** Validate's Gate is a numbered list (1–5). Insert a new numbered item between steps 4 and 5 using the shared **Gate-read bullet** wording, adapted to a numbered item:
   ```text
   5. Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, `2_research.md`, `3_plan.md`) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Implement produced …") so the read is auditable.
   ```
3. Renumber the previously-existing step 5 to step 6.
4. **After-workflow edit.** Locate `## After the workflow completes`. Currently the section reads: write `4_validate.md` → then the prose paragraph "Then commit the validation report and `context.yaml` together. Invoke `Skill(git-commit)` first…" with the `git add` example, then push. Insert a new instruction *before* the "Then commit…" sentence, using the shared **Summary write instruction** wording with `<next agent>` = "Document" and `<this step doc>` = "`4_validate.md`":
   ```text
   Then overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (Document) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what Validate accomplished (senior-review and QA verdicts, iteration counts, e2e result), (2) key findings and decisions during review and any fixes applied, (3) relevant context for the Document phase — surfaces that changed in unexpected ways during fixes, any tradeoffs the user should know about in the PR description, anything that isn't self-evident from `4_validate.md`.
   ```
5. Do not change the Workflow, Push-failure escalation, "If the skill cannot complete", or "If QA cannot reach a green e2e suite" sections.

**Commit:** `feat(validate): read workflow.summary on entry, write it before commit`

---

### Task 9: Add gate-read and summary-write to the Document agent

**Files:** `.claude/agents/document.md`

**Acceptance:**

```
document.md
  - Gate section: Document uses a numbered list (1–5). A new numbered item is inserted between existing step 4 (read full diff) and existing step 5 (read `1_spec.md`)
  - the new item directs the agent to read `workflow.summary` first as the primary handoff narrative, with prior step docs read on demand only, and includes the opening-message acknowledgment instruction
  - existing step 5 is renumbered to step 6
  - Commit-and-push-documentation section: an explicit instruction is inserted BEFORE the `git add ... git commit` example
  - the instruction directs the agent to overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering the three required content areas, with next-phase context aimed at workflow completion (PR review)
  - no other section of document.md is modified — Documentation Audit, PR Description, and Completion sections unchanged
  - existing commit message wording (`docs: update documentation for ...`) is unchanged
```

**Implementation:**

1. Open `.claude/agents/document.md`.
2. **Gate edit.** Document's Gate is a numbered list (1–5). Insert a new numbered item between steps 4 and 5:
   ```text
   5. Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, `2_research.md`, `3_plan.md`, `4_validate.md`) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, Validate produced …") so the read is auditable.
   ```
3. Renumber the previously-existing step 5 to step 6.
4. **Commit-and-push-documentation edit.** Locate `## Commit and push documentation`. The section opens with: "Once the documentation audit is complete and every affected documentation surface has been updated, commit those changes and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage only the files you actually modified…" followed by the `git add` example. Insert a new instruction *before* the "commit those changes" sentence:
   ```text
   Once the documentation audit is complete and every affected documentation surface has been updated, overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — even though Document is the last pipeline step, the summary serves as the final orientation record for a developer who picks up the PR. Cover three areas in order: (1) what Document accomplished (what documentation surfaces were updated, what new docs were created), (2) key findings and decisions during the documentation audit (gaps closed, surfaces deliberately not updated and why), (3) relevant context for the human reviewer — what to look at first in the PR, anything in the diff or docs that warrants scrutiny.
   ```
   The existing "commit those changes and `context.yaml` together…" sentence follows immediately after.
5. Do not change the Documentation Audit, PR Description, Push-failure escalation, or Completion sections.

**Commit:** `feat(document): read workflow.summary on entry, write it before commit`

---

## Shared wording reference

These two strings appear (with role-specific substitutions) across Tasks 4–9. Codify here once so the Implementer reuses them verbatim and any future edit changes one place.

### Gate-read bullet (Tasks 5–9; not used in Task 4 — Define has no prior summary)

> Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`<prior step doc list>`) only on demand when you need a specific detail the summary does not carry. Acknowledge in your opening message that you have read the summary (e.g. "Per `workflow.summary`, `<prior agent>` produced …") so the read is auditable.

Substitutions per task:

| Task | `<prior step doc list>` | `<prior agent>` |
|------|---|---|
| 5 (Research) | `1_spec.md`, etc. | Define |
| 6 (Plan) | `1_spec.md`, `2_research.md`, etc. | Research |
| 7 (Implement) | `1_spec.md`, `3_plan.md`, etc. | Plan |
| 8 (Validate) | `1_spec.md`, `2_research.md`, `3_plan.md` | Implement |
| 9 (Document) | `1_spec.md`, `2_research.md`, `3_plan.md`, `4_validate.md` | Validate |

### Summary write instruction (Tasks 4–9, all six agents)

> Overwrite `workflow.summary` in `context.yaml` with a fresh ~300–500 token prose summary of this step's outcome. The summary is prose (not bullets), overwritten (not appended), and written to be self-contained — the next agent (`<next agent>`) should be able to start from `workflow.summary` alone in the common case. Cover three areas in order: (1) what `<this step>` accomplished, (2) key findings and decisions made during the step (including why, when non-obvious), (3) relevant context for the `<next phase>` — `<role-specific context-area examples>`.

Substitutions per task (the per-task instruction in each task block above already inlines these):

| Task | `<next agent>` | `<this step>` | `<role-specific context-area examples>` |
|------|---|---|---|
| 4 (Define) | Research | Define | scope boundaries; anything from the conversation that shaped `1_spec.md` but isn't self-evident from the spec itself |
| 5 (Research) | Plan | Research | patterns to follow, gaps, scope boundaries; anything that shaped `2_research.md` but isn't self-evident from the doc itself |
| 6 (Plan) | Implement | Plan | DRY/YAGNI calls, file-map intent, task ordering rationale that isn't self-evident from `3_plan.md` itself |
| 7 (Implement) | Validate | Implement | known weak spots, diff areas warranting extra senior-review attention, test-coverage gaps not obvious from the diff |
| 8 (Validate) | Document | Validate | surfaces that changed during fixes, tradeoffs to capture in the PR description |
| 9 (Document) | the human reviewer | Document | what to look at first in the PR; anything in the diff or docs that warrants scrutiny |

---

## Out of Scope

These items are deliberately excluded from this implementation. Documenting them prevents scope creep during Implement and Validate.

- **Spec `**Status:** Draft → Approved` automation.** Surfaced in Research §"Architectural Context" and Research §"Open Questions" — the Research agent's gate hard-checks for `**Status:** Approved` in `1_spec.md`, but the `/feature` orchestrator's Approval Gate never writes that string back to the spec when the user approves. Pre-existing inconsistency, not introduced by this feature. Out of scope per spec Non-Goals (no orchestrator behavior changes beyond `/compact`) and per Research's recommendation. Flagged here for visibility only.
- **Focus instructions for `/compact`.** Bare `/compact` is what the spec calls for; `/compact [instructions]` would allow targeting specific content to preserve. Not in scope per spec Constraints and Research §"Open Questions". The bare form is simpler and matches the spec's stated intent.
- **Enforcing the ~300–500 token budget mechanically.** The budget is a guideline for the agent to follow, not a hard limit any tool enforces. Out of scope per spec Constraints.
- **Compacting subagent context windows.** Per Research §"Architectural Context", subagents already run in isolated context windows; `/compact` only affects the orchestrator's. The `workflow.summary` field is the mechanism that addresses the subagent-side cold-start cost. No additional change needed.
- **Migrating in-flight features without a `workflow.summary` field.** Per spec Constraints, missing fields default to `""` and the field appears on the first step boundary after this change lands. No migration step needed.
- **Tests.** The repo has no test suite. Validation is the dry-run acceptance check in spec Acceptance Criterion #8 plus markdown/YAML rendering eyeball checks. Implement does not write tests for these tasks.
- **Updating the in-flight feature's own `context.yaml`** beyond the per-step `workflow.summary` writes that this feature's own pipeline already performs. The in-flight `context.yaml` is already the worked example for the new field's shape.
