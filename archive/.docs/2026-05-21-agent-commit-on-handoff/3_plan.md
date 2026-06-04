# Plan: Agent Commit on Handoff

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-05-21

> **For agentic workers:** Execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every pipeline agent (Define, Research, Plan, Implement, Validate, Document) and the `/feature` orchestrator commit their own output files plus `context.yaml`, then push the feature branch, before handing control back. Standardizes per-step git boundaries and keeps the remote in sync with local at every checkpoint.

**Architecture:** All edits are in-place changes to existing instruction prose inside `.claude/`. No application code. No new files. Seven files modified: six agents + one orchestrator skill. Three of the six agents (Research, Validate, Document) also need `git-commit` appended to their frontmatter `skills:` array so they can invoke the skill. Every new commit step uses explicit `git add <path>` (never `git add -A`), invokes the `git-commit` skill, and writes a Conventional Commits message with no AI attribution. Every new push step has the same boilerplate push-failure escalation branch that writes `workflow.escalated: true` and `workflow.escalation_reason` to `context.yaml` and returns.

**Tech Stack:** Markdown instruction files. No compiled code. Verification is file inspection — the project has no automated test suite for `.claude/` instruction changes (research §"Key Insights for the Planner", note 7). The implement skill's coverage gate does not apply.

---

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

None. This feature is entirely in-place edits.

### Modified Files

| File | What Changes | Why |
|------|-------------|-----|
| `.claude/agents/define.md` | Insert a commit step between the existing "write spec" and "push branch" steps; add a push-failure escalation branch attached to the existing push step. | Spec Requirement: "Define agent". Research §"Gaps", item 1. |
| `.claude/agents/research.md` | Append `git-commit` to the frontmatter `skills:` array; append two new steps (commit `2_research.md` + artifacts + `context.yaml`; `git push`) to the "After the workflow completes" section; add a push-failure escalation branch. | Spec Requirement: "Research agent". Research §"Gaps", item 2; §"Patterns and Conventions", `skills:` arrays. |
| `.claude/agents/plan.md` | Replace step 3 ("Commit the plan with a conventional commit message") with a broadened step that stages `3_plan.md` + `context.yaml` together; append a `git push` step; add a push-failure escalation branch. | Spec Requirement: "Plan agent". Research §"Gaps", item 3. |
| `.claude/agents/implement.md` | Append a new "After all tasks complete" section: conditional commit of `context.yaml` (only if dirty) followed by an unconditional `git push`; add a push-failure escalation branch reusing the existing escalation YAML block style. | Spec Requirement: "Implement agent". Research §"Gaps", item 4; §"Key Insights", note 3 (conditional commit). |
| `.claude/agents/validate.md` | Append `git-commit` to the frontmatter `skills:` array; append two new steps to "After the workflow completes" (commit `4_validate.md` + `context.yaml`; `git push`); add a push-failure escalation branch. | Spec Requirement: "Validate agent". Research §"Gaps", item 5; §"Patterns and Conventions", `skills:` arrays. |
| `.claude/agents/document.md` | Append `git-commit` to the frontmatter `skills:` array; insert an explicit commit step (all docs changed + `context.yaml`) and a `git push` between the "Documentation Audit" section and the "PR Description" section; add a push-failure escalation branch. | Spec Requirement: "Document agent". Research §"Gaps", item 6; §"Patterns and Conventions", `skills:` arrays. |
| `.claude/skills/feature/SKILL.md` | Append two steps (6: commit `context.yaml`; 7: `git push`) to the Post-return protocol; add a push-failure escalation branch that halts the orchestrator before invoking the next agent. | Spec Requirement: "Orchestrator post-handoff protocol". Research §"Gaps", item 7; §"Architectural Context", note 4 (orchestrator's own push-failure halt). |

### Deleted Files

None.

---

## Verification approach (applies to every task)

This feature has no automated test suite — the work is instruction prose, and the project has no test runner for `.claude/` (research §"Key Insights", note 7). Each task therefore replaces the standard "Tests" block with an explicit **Verification** checklist of file-inspection assertions. After every edit, re-read the file and confirm each assertion holds before committing.

Acceptance criterion 11 ("Running the full pipeline end-to-end on a sample feature produces at least one commit per pipeline step") is satisfied by a final inspection task (Task 8) that asserts, by reading each agent file, that the required commit + push steps and the required commit-message strings are present in the instructions. Research §"Key Insights", note 6 documents this choice — option (b) "documentation check that asserts each agent's instructions contain the required commit + push steps" — as more reproducible than running the pipeline on a throwaway feature.

---

## Implementation Tasks

Tasks are ordered to match the runtime sequence of the pipeline so reviewers can read the plan in the order the orchestrator will execute the changed instructions. Task 8 is the cross-cutting verification step.

---

### Task 1: Add commit step to Define agent

**Files:** `.claude/agents/define.md`

**Verification:**

```
File: .claude/agents/define.md
- The "After the workflow completes" section contains 5 numbered steps (was 4).
- Step 1 (write 1_spec.md) is unchanged.
- New step 2 stages `1_spec.md` and `context.yaml` with explicit `git add` paths.
- New step 2 instructs invoking Skill(git-commit) before `git commit`.
- New step 2's commit message is exactly: `docs(spec): add spec for <feature name>`.
- Step 3 is the existing `git push -u origin <feature.branch from context.yaml>` line.
- A push-failure escalation block appears immediately after the push step, with the YAML showing `escalated: true` and `escalation_reason` and the comment `# Merge into existing workflow block — do not replace other fields`.
- Step 4 is the existing `gh pr create --draft ...` line (renumbered from 3).
- Step 5 is the existing "Return." line (renumbered from 4).
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Insert commit step between write-spec and push-branch**

  In `.claude/agents/define.md`, replace the existing "After the workflow completes" block:

  ```markdown
  1. Use the `spec` skill to format the agreed design into a `1_spec.md` document. Write it to `<feature.folder>/1_spec.md`.
  2. Push the branch to remote with `git push -u origin <feature.branch from context.yaml>`.
  3. Run `gh pr create --draft --base <feature.base_branch from context.yaml> --title "<feature name>"`. Use the `create-pr` skill for title format. Leave the PR body minimal — it will be written by the Document agent at the end of the workflow.
  4. Return. The feature orchestrator will present the spec for user approval.
  ```

  with:

  ```markdown
  1. Use the `spec` skill to format the agreed design into a `1_spec.md` document. Write it to `<feature.folder>/1_spec.md`.
  2. Commit the spec and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage and commit only those two files:

     ```bash
     git add <feature.folder>/1_spec.md <feature.folder>/context.yaml
     git commit -m "docs(spec): add spec for <feature.name from context.yaml>"
     ```

     Do not use `git add -A` or `git add .` — stage explicit paths only.
  3. Push the branch to remote with `git push -u origin <feature.branch from context.yaml>`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return — do not proceed to the PR step.
  4. Run `gh pr create --draft --base <feature.base_branch from context.yaml> --title "<feature name>"`. Use the `create-pr` skill for title format. Leave the PR body minimal — it will be written by the Document agent at the end of the workflow.
  5. Return. The feature orchestrator will present the spec for user approval.

  ### Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Define step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
  ```

- [ ] **Step 2: Verify Define agent file**

  Re-read `.claude/agents/define.md` and confirm every assertion in the Verification block above.

**Commit:**

```bash
git add .claude/agents/define.md
git commit -m "feat(define): commit spec and escalate on push failure"
```

---

### Task 2: Add git-commit skill and commit step to Research agent

**Files:** `.claude/agents/research.md`

**Verification:**

```
File: .claude/agents/research.md
- Frontmatter `skills:` array contains `git-commit` as its last entry.
- The "After the workflow completes" section contains 4 numbered steps (was 2).
- Steps 1 and 2 (write 2_research.md, register artifacts) are unchanged.
- New step 3 stages `<feature.folder>/2_research.md`, all paths from `context.yaml` artifacts, and `<feature.folder>/context.yaml` with explicit `git add` paths.
- New step 3 instructs invoking Skill(git-commit) before `git commit`.
- New step 3's commit message is exactly: `docs(research): add research for <feature name>`.
- New step 4 is `git push`.
- A push-failure escalation block appears after step 4 with the same shape as Define's.
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Append git-commit to frontmatter skills array**

  In `.claude/agents/research.md`, replace:

  ```yaml
  skills:
    - agent-context
    - analyze-code
    - find-patterns
    - web-search
    - frontend-ui-engineering
    - ui-design-brain
    - research
  ```

  with:

  ```yaml
  skills:
    - agent-context
    - analyze-code
    - find-patterns
    - web-search
    - frontend-ui-engineering
    - ui-design-brain
    - research
    - git-commit
  ```

- [ ] **Step 2: Append commit and push steps to "After the workflow completes"**

  In `.claude/agents/research.md`, replace the entire "After the workflow completes" section:

  ```markdown
  ## After the workflow completes

  1. Write the research findings to `<feature.folder>/2_research.md` using the template at `.claude/skills/research/template.md` as the structure.
  2. For every artifact file noted during research, save it to `<feature.folder>/artifacts/` and append an entry to the `artifacts` list in `context.yaml` with its path relative to `feature.folder`, a description, and `created_by: research`.
  ```

  with:

  ```markdown
  ## After the workflow completes

  1. Write the research findings to `<feature.folder>/2_research.md` using the template at `.claude/skills/research/template.md` as the structure.
  2. For every artifact file noted during research, save it to `<feature.folder>/artifacts/` and append an entry to the `artifacts` list in `context.yaml` with its path relative to `feature.folder`, a description, and `created_by: research`.
  3. Commit the research, any artifacts, and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage and commit only those files:

     ```bash
     git add <feature.folder>/2_research.md <feature.folder>/artifacts/ <feature.folder>/context.yaml
     git commit -m "docs(research): add research for <feature.name from context.yaml>"
     ```

     If no files were saved to `<feature.folder>/artifacts/`, omit that path from `git add`. Do not use `git add -A` or `git add .` — stage explicit paths only.
  4. Push the branch with `git push`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return.

  ## Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Research step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
  ```

- [ ] **Step 3: Verify Research agent file**

  Re-read `.claude/agents/research.md` and confirm every assertion in the Verification block above.

**Commit:**

```bash
git add .claude/agents/research.md
git commit -m "feat(research): commit findings and escalate on push failure"
```

---

### Task 3: Broaden Plan agent commit step and add push

**Files:** `.claude/agents/plan.md`

**Verification:**

```
File: .claude/agents/plan.md
- Frontmatter `skills:` array still contains `git-commit` (unchanged from current).
- The "After the workflow completes" section contains 4 numbered steps (was 3).
- Steps 1 and 2 (write 3_plan.md, scan skills + update recommended_skills) are unchanged.
- Step 3 (previously "Commit the plan with a conventional commit message") now stages both `<feature.folder>/3_plan.md` and `<feature.folder>/context.yaml` explicitly.
- Step 3 instructs invoking Skill(git-commit) before `git commit`.
- Step 3's commit message is exactly: `docs(plan): add implementation plan for <feature name>`.
- New step 4 is `git push`.
- A push-failure escalation block appears after step 4 with the same shape as Define's.
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Replace step 3 with a widened commit step and add a push step**

  In `.claude/agents/plan.md`, replace:

  ```markdown
  3. Commit the plan with a conventional commit message.
  ```

  with:

  ```markdown
  3. Commit the plan and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage and commit only those two files:

     ```bash
     git add <feature.folder>/3_plan.md <feature.folder>/context.yaml
     git commit -m "docs(plan): add implementation plan for <feature.name from context.yaml>"
     ```

     Do not use `git add -A` or `git add .` — stage explicit paths only.
  4. Push the branch with `git push`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return.

  ## Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Plan step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
  ```

- [ ] **Step 2: Verify Plan agent file**

  Re-read `.claude/agents/plan.md` and confirm every assertion in the Verification block above.

**Commit:**

```bash
git add .claude/agents/plan.md
git commit -m "feat(plan): widen commit to context.yaml and push on completion"
```

---

### Task 4: Add conditional end-of-step commit and push to Implement agent

**Files:** `.claude/agents/implement.md`

**Verification:**

```
File: .claude/agents/implement.md
- Frontmatter `skills:` array still contains `git-commit` (unchanged from current).
- A new "After all tasks complete" section exists between "After each task completes" and "If the skill cannot complete".
- The new section instructs running `git status --porcelain <feature.folder>/context.yaml` and only committing if the output is non-empty.
- The conditional commit stages only `<feature.folder>/context.yaml` and invokes Skill(git-commit) first.
- The conditional commit message is exactly: `chore(context): update workflow checkpoint`.
- The push step (`git push`) is unconditional — runs whether or not the commit happened.
- A push-failure escalation block appears immediately after the push step, reusing the same YAML shape as the existing escalation block in this file.
- The existing per-task commit behavior described in the linked implement skill is not duplicated or contradicted.
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Insert "After all tasks complete" section**

  In `.claude/agents/implement.md`, insert a new section between the existing "After each task completes" section and the existing "If the skill cannot complete" section:

  ```markdown
  ## After all tasks complete

  Once the implement skill signals all tasks are done, perform a final end-of-step sync before returning.

  1. Check whether `context.yaml` has uncommitted changes (the last `workflow.checkpoint` update may not yet be in a commit):

     ```bash
     git status --porcelain <feature.folder>/context.yaml
     ```

     If the output is non-empty, commit `context.yaml`. Invoke `Skill(git-commit)` first, then stage and commit only that file:

     ```bash
     git add <feature.folder>/context.yaml
     git commit -m "chore(context): update workflow checkpoint"
     ```

     If the output is empty, skip the commit — there is nothing to add. Do not produce an empty commit.

  2. Push the branch with `git push`. Run this unconditionally (whether or not step 1 produced a commit) so any per-task commits from the implement skill are flushed to the remote. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return.
  ```

- [ ] **Step 2: Append push-failure escalation block**

  Immediately after the new "After all tasks complete" section and before the existing "If the skill cannot complete" section, insert:

  ```markdown
  ## Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Implement step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
  ```

- [ ] **Step 3: Verify Implement agent file**

  Re-read `.claude/agents/implement.md` and confirm every assertion in the Verification block above. Confirm the existing per-task commit guidance in `.claude/skills/implement/SKILL.md` is not contradicted — the new end-of-step commit is conditional and additive.

**Commit:**

```bash
git add .claude/agents/implement.md
git commit -m "feat(implement): add end-of-step context commit and push"
```

---

### Task 5: Add git-commit skill and commit step to Validate agent

**Files:** `.claude/agents/validate.md`

**Verification:**

```
File: .claude/agents/validate.md
- Frontmatter `skills:` array contains `git-commit` (was just `agent-context`).
- The "After the workflow completes" section keeps the existing `4_validate.md` write instruction.
- New numbered steps follow: stage-and-commit `4_validate.md` + `context.yaml`; `git push`.
- The commit step instructs invoking Skill(git-commit) first.
- The commit message is exactly: `docs(validate): add validation report for <feature name>`.
- A push-failure escalation block appears after the push step, reusing the same YAML shape as the existing escalation block in this file.
- The existing "If the skill cannot complete" section is unchanged.
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Append git-commit to frontmatter skills array**

  In `.claude/agents/validate.md`, replace:

  ```yaml
  skills:
    - agent-context
  ```

  with:

  ```yaml
  skills:
    - agent-context
    - git-commit
  ```

- [ ] **Step 2: Add commit and push steps after the 4_validate.md template**

  In `.claude/agents/validate.md`, immediately after the closing triple-backtick of the `## After the workflow completes` markdown block (the one that defines the `4_validate.md` template ending with the "Evidence" section), append:

  ```markdown

  Then commit the validation report and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage and commit only those files:

  ```bash
  git add <feature.folder>/4_validate.md <feature.folder>/context.yaml
  git commit -m "docs(validate): add validation report for <feature.name from context.yaml>"
  ```

  Do not use `git add -A` or `git add .` — stage explicit paths only.

  Push the branch with `git push`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return.

  ## Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Validate step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
  ```

  Place this new content **before** the existing `## If the skill cannot complete` section so the section order reads: After the workflow completes → Push-failure escalation → If the skill cannot complete.

- [ ] **Step 3: Verify Validate agent file**

  Re-read `.claude/agents/validate.md` and confirm every assertion in the Verification block above.

**Commit:**

```bash
git add .claude/agents/validate.md
git commit -m "feat(validate): commit report and escalate on push failure"
```

---

### Task 6: Add git-commit skill and commit step to Document agent

**Files:** `.claude/agents/document.md`

**Verification:**

```
File: .claude/agents/document.md
- Frontmatter `skills:` array contains `git-commit` (was `agent-context`, `create-pr`).
- A new "## Commit and push documentation" section exists between "## Documentation Audit" and "## PR Description".
- The new section instructs staging only the documentation files that the agent actually modified plus `<feature.folder>/context.yaml` — explicit `git add` paths, never `git add -A`.
- The new section instructs invoking Skill(git-commit) before `git commit`.
- The commit message is exactly: `docs: update documentation for <feature name>`.
- The new section ends with a `git push` instruction.
- A push-failure escalation block appears immediately after the new section and before the "## PR Description" section, with the same YAML shape used in the other agents.
- The existing "## PR Description" and "## Completion" sections are otherwise unchanged. The phrase "Once all documentation is updated and committed" in PR Description still reads correctly (commit step now exists explicitly above it).
- No `git add -A` or `git add .` appears anywhere in the file.
```

**Implementation:**

- [ ] **Step 1: Append git-commit to frontmatter skills array**

  In `.claude/agents/document.md`, replace:

  ```yaml
  skills:
    - agent-context
    - create-pr
  ```

  with:

  ```yaml
  skills:
    - agent-context
    - create-pr
    - git-commit
  ```

- [ ] **Step 2: Insert commit + push section between Documentation Audit and PR Description**

  In `.claude/agents/document.md`, insert immediately before the existing `## PR Description` heading:

  ```markdown
  ## Commit and push documentation

  Once the documentation audit is complete and every affected documentation surface has been updated, commit those changes and `context.yaml` together. Invoke `Skill(git-commit)` first, then stage only the files you actually modified — do **not** use `git add -A` or `git add .`.

  ```bash
  # Example — replace the paths with the exact files you touched
  git add README.md CLAUDE.md docs/<feature-doc>.md <feature.folder>/context.yaml
  git commit -m "docs: update documentation for <feature.name from context.yaml>"
  ```

  Push the branch with `git push`. If the push fails (non-zero exit), write the push-failure escalation below to `context.yaml` and return — do not proceed to the PR description update or draft removal.

  ## Push-failure escalation

  If `git push` exits non-zero (non-fast-forward, network error, auth failure), write to `context.yaml` and return:

  ```yaml
  # Merge into existing workflow block — do not replace other fields
  workflow:
    escalated: true
    escalation_reason: |
      git push failed during the Document step.
      [Exit code and the exact stderr from the failed push]
      [Assessment: e.g. branch out of date with remote, missing credentials, network error]
  ```

  Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.

  ```

- [ ] **Step 3: Verify Document agent file**

  Re-read `.claude/agents/document.md` and confirm every assertion in the Verification block above. Confirm "## PR Description" and "## Completion" sections are unchanged in content.

**Commit:**

```bash
git add .claude/agents/document.md
git commit -m "feat(document): commit docs and escalate on push failure"
```

---

### Task 7: Add commit + push to orchestrator post-return protocol

**Files:** `.claude/skills/feature/SKILL.md`

**Verification:**

```
File: .claude/skills/feature/SKILL.md
- The "### Post-return protocol" section contains 7 numbered steps (was 5).
- Steps 1-5 are unchanged in meaning (read context.yaml; check escalated; append completed_steps; advance current_step; write context.yaml).
- New step 6 commits `<feature_folder>/context.yaml` with explicit `git add`.
- New step 6 instructs invoking Skill(git-commit) before `git commit`.
- New step 6's commit message uses the template: `chore(context): advance workflow to <next step>` — exact string.
- New step 7 runs `git push`.
- An orchestrator push-failure handling instruction is present that halts the orchestrator (announces failure to the user and stops without invoking the next agent) — distinct from the agent escalation contract because the orchestrator has no agent above it to surface the escalation through.
- No `git add -A` or `git add .` appears in the protocol.
- The "### Approval Gate" section is unchanged — it already runs the post-return protocol on approval, so the new commit step flows through automatically.
- The "### Completion" section is unchanged.
```

**Implementation:**

- [ ] **Step 1: Append commit and push steps to the post-return protocol**

  In `.claude/skills/feature/SKILL.md`, replace the existing post-return protocol:

  ```markdown
  ### Post-return protocol

  Run this after every agent returns:

  1. Read `context.yaml` from `feature_folder`.
  2. If `workflow.escalated` is `true`: halt immediately. Tell the user: `"Pipeline halted — " + workflow.escalation_reason`. Do not update `context.yaml`. Do not invoke the next agent. Stop.
  3. Append the completed step name to `workflow.completed_steps` (initialize to `[]` if the key is absent).
  4. Set `workflow.current_step` to the next step name (see sequence table below).
  5. Write the updated `context.yaml`.
  ```

  with:

  ```markdown
  ### Post-return protocol

  Run this after every agent returns:

  1. Read `context.yaml` from `feature_folder`.
  2. If `workflow.escalated` is `true`: halt immediately. Tell the user: `"Pipeline halted — " + workflow.escalation_reason`. Do not update `context.yaml`. Do not invoke the next agent. Stop.
  3. Append the completed step name to `workflow.completed_steps` (initialize to `[]` if the key is absent).
  4. Set `workflow.current_step` to the next step name (see sequence table below).
  5. Write the updated `context.yaml`.
  6. Commit the updated `context.yaml`. Invoke `Skill(git-commit)` first, then:

     ```bash
     git add <feature_folder>/context.yaml
     git commit -m "chore(context): advance workflow to <next step>"
     ```

     Substitute `<next step>` with the value just written to `workflow.current_step` (e.g. `research`, `plan`, `implement`, `validate`, `document`, `complete`). Do not use `git add -A` or `git add .`.
  7. Push the branch with `git push`. If the push fails (non-zero exit), halt the orchestrator: announce `"Pipeline halted — git push failed during post-return protocol: <stderr>"` to the user and stop. Do not invoke the next agent. The orchestrator has no agent above it to surface escalation through, so it halts itself rather than writing to `workflow.escalated`.
  ```

- [ ] **Step 2: Verify orchestrator skill file**

  Re-read `.claude/skills/feature/SKILL.md` and confirm every assertion in the Verification block above. Confirm "### Approval Gate" still says "run the post-return protocol (completed: `define`, next: `research`), then announce ..." — the new commit + push steps flow through this call without further changes.

**Commit:**

```bash
git add .claude/skills/feature/SKILL.md
git commit -m "feat(feature): commit and push context.yaml after each step transition"
```

---

### Task 8: Final cross-cutting inspection

**Files:** None modified — this task is read-only verification across all seven files changed in Tasks 1-7.

**Purpose:** Satisfy acceptance criterion 11 by asserting that every required commit + push step and every required commit-message string is present in the instructions. This is the documentation-check option described in Research §"Key Insights", note 6 — chosen over a live pipeline run for reproducibility.

**Verification:**

- [ ] **Step 1: Confirm acceptance criteria 1-10 by file inspection**

  Read each of the seven modified files and check the corresponding spec acceptance criterion:

  | Spec AC | File | What to look for |
  |---|---|---|
  | 1 | `.claude/agents/define.md` | A commit step for `1_spec.md` + `context.yaml` appears **before** the `git push -u origin` line. Commit message reads `docs(spec): add spec for <feature name>`. |
  | 2 | `.claude/agents/research.md` | Commit step for `2_research.md`, artifacts, and `context.yaml` exists. A `git push` step follows. Commit message reads `docs(research): add research for <feature name>`. |
  | 3 | `.claude/agents/plan.md` | Step 3 stages `3_plan.md` + `context.yaml` (not just `3_plan.md`). A `git push` step follows. Commit message reads `docs(plan): add implementation plan for <feature name>`. There is no duplicate "Commit the plan" instruction left from before. |
  | 4 | `.claude/agents/implement.md` | The new "After all tasks complete" section has a `git status --porcelain` check guarding the commit. Push runs unconditionally. Commit message reads `chore(context): update workflow checkpoint`. |
  | 5 | `.claude/agents/validate.md` | Commit step for `4_validate.md` + `context.yaml` exists. A `git push` step follows. Commit message reads `docs(validate): add validation report for <feature name>`. |
  | 6 | `.claude/agents/document.md` | A new "Commit and push documentation" section exists between "Documentation Audit" and "PR Description". Commit message reads `docs: update documentation for <feature name>`. |
  | 7 | `.claude/skills/feature/SKILL.md` | Steps 6 and 7 of the post-return protocol commit and push `context.yaml`. Commit message template reads `chore(context): advance workflow to <next step>`. |
  | 8 | All seven files | Every new commit instruction references `Skill(git-commit)` (or otherwise invokes the skill before `git commit`). |
  | 9 | All seven files | No new commit message contains `Co-Authored-By`, `Generated by`, `🤖`, Claude, Anthropic, or any AI attribution. All are Conventional Commits, lowercase, imperative, no trailing period. |
  | 10 | All seven files | No instance of `git add -A` or `git add .` exists in any new content. Every stage step uses explicit paths. |

- [ ] **Step 2: Confirm acceptance criterion 11 (per-step commits would appear)**

  Read each of the seven files and confirm — without running the pipeline — that an end-to-end run would produce at minimum:

  - 1 commit from Define (`docs(spec): ...`)
  - 1 commit from the orchestrator post-return protocol after Define (`chore(context): advance workflow to research`)
  - 1 commit from Research (`docs(research): ...`)
  - 1 commit from the orchestrator post-return protocol after Research (`chore(context): advance workflow to plan`)
  - 1 commit from Plan (`docs(plan): ...`)
  - 1 commit from the orchestrator post-return protocol after Plan (`chore(context): advance workflow to implement`)
  - N commits from Implement (one per task, from the implement skill) + 0-or-1 conditional `chore(context): update workflow checkpoint`
  - 1 commit from the orchestrator post-return protocol after Implement (`chore(context): advance workflow to validate`)
  - 1 commit from Validate (`docs(validate): ...`)
  - 1 commit from the orchestrator post-return protocol after Validate (`chore(context): advance workflow to document`)
  - 1 commit from Document (`docs: update documentation for ...`)
  - 1 commit from the orchestrator post-return protocol after Document (`chore(context): advance workflow to complete`)

  At least one commit per pipeline step is therefore guaranteed by the instructions.

- [ ] **Step 3: Confirm push-failure escalation contract is uniform across all six agents**

  Read each of the six agent files (`define.md`, `research.md`, `plan.md`, `implement.md`, `validate.md`, `document.md`) and confirm each one contains a push-failure block that:

  - Sets `workflow.escalated: true`
  - Sets `workflow.escalation_reason` to a multi-line string describing the push failure (exit code, stderr, assessment)
  - Includes the comment `# Merge into existing workflow block — do not replace other fields`
  - Tells the agent to return without notifying the user directly

  Also confirm `.claude/skills/feature/SKILL.md` step 7 has the orchestrator-side variant (announce-and-halt) rather than the agent-side escalation YAML, since the orchestrator has no agent above it.

**Commit:**

This task makes no file changes — no commit. If verification fails, return to the relevant earlier task, fix the file, and re-run that task's `commit` step.

---

## Out of Scope

Anything explicitly excluded from this implementation. Documenting this prevents scope creep during implementation.

- **Changing what each agent writes or how it writes it.** The file outputs themselves (`1_spec.md`, `2_research.md`, etc.) are unchanged in content. Only the post-write commit + push behavior is added. (Spec §"Non-Goals", item 1.)
- **Changing the orchestration sequence or the approval gate.** Define → Research → Plan → Implement → Validate → Document remains. The approval gate between Define and Research is unchanged in behavior — it already calls the post-return protocol on approval, so the new commit + push steps flow through automatically. (Spec §"Non-Goals", item 2.)
- **New commit hooks or CI checks.** The existing `.claude/hooks/skill-check.sh` already nudges agents to invoke `git-commit` before `git commit`. No new hooks are added. (Spec §"Non-Goals", item 3.)
- **Squashing or rewriting commits at the end of the pipeline.** Each step keeps its own commit; per-step audit trail is the explicit goal. (Spec §"Non-Goals", item 4.)
- **Changing Implement's per-task commit behavior.** The per-task commits inside `.claude/skills/implement/SKILL.md` step 7 are untouched. The only addition is a conditional end-of-step `context.yaml` commit plus a single push. (Spec §"Non-Goals", item 5.)
- **Automatic resolution of push conflicts.** If `git push` fails for any reason (non-fast-forward, auth, network), the agent escalates and halts. No automatic pull-and-retry. The user resolves remote state manually. (Spec §"Non-Goals", item 6.)
- **Changes to how the Plan agent recommends skills or how the Validate agent runs reviews.** Both keep their existing internal workflows. (Spec §"Non-Goals", item 7.)
- **Fixing the `Status: Draft` → `Status: Approved` flip in `1_spec.md`.** Research §"Open Questions" flagged that no agent currently flips this field, yet the Research agent's gate requires it. This is a pre-existing gap unrelated to commit-on-handoff. Out of scope for this feature — the spec doesn't address it and the existing approval flow presumably works (the user or Claude flips it implicitly during the Define conversation). If the new Define commit step commits the spec while it is still `Status: Draft`, the later flip-to-Approved will land in whichever commit the orchestrator or a follow-up agent produces — acceptable for this feature.
- **Running the pipeline on a sample feature to verify end-to-end.** Task 8 uses documentation inspection instead — reproducible, deterministic, no LLM cost. The spec's acceptance criterion 11 ("Running the full pipeline end-to-end on a sample feature produces at least one commit per pipeline step") is satisfied indirectly via Task 8 step 2, which proves by reading the instructions that a run would produce the required commits. A live pipeline run can be done by the user post-merge as smoke testing.
- **Updating the README or CLAUDE.md to describe the per-step commit behavior.** Research §"Codebase Areas Affected" notes the README does not currently describe per-step commit behavior and that this is out-of-scope unless the Document agent decides this rises to README-level significance during a real pipeline run. For this feature's own pipeline (when run on itself), the Document agent will make that call. No pre-emptive update to README or CLAUDE.md is planned here.
