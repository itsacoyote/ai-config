# Workflow Orchestrator Implementation Plan

> **For agentic workers:** Execute this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize pipeline coordination into the `feature` skill so agents are pure domain workers with no knowledge of sequencing.

**Architecture:** The `feature` skill is rewritten as the full pipeline orchestrator — it owns the step sequence, transition announcements, spec approval gate, escalation handling, and all `context.yaml` step-transition writes. Agents lose their Handoff sections and stop invoking each other; they do their job, optionally signal escalation via `context.yaml`, and return. Internal sub-orchestration within agents (Code Reviewer loops in Implement, Senior/QA loops in Validate) is unchanged.

**Tech Stack:** Markdown instruction files for skills and agents. No compiled code. Verification is manual file inspection.

---

## File Map

**Modified:**
- `.claude/skills/feature/SKILL.md` — full rewrite as pipeline orchestrator
- `.claude/skills/agent-context/template.yaml` — add `escalated` and `escalation_reason` to the `workflow` block
- `.claude/skills/agent-context/SKILL.md` — document the two new escalation fields and when agents write them
- `.claude/agents/define.md` — remove step 7 (user approval dialogue, context.yaml update, Research invocation); update Output section
- `.claude/agents/research.md` — remove last 3 lines of Output section (context.yaml update, announcement, Plan invocation)
- `.claude/agents/plan.md` — remove the 3 lines after "Once complete, commit the plan" (context.yaml update, announcement, Implement invocation)
- `.claude/agents/implement.md` — replace "Notify and halt" in Escalation with context.yaml write; replace Handoff section with a return note
- `.claude/agents/validate.md` — replace "Notify and halt" in Escalation with context.yaml write; remove last 3 lines of Completion (context.yaml update, announcement, Document invocation)
- `.claude/agents/document.md` — remove steps 2 and 3 from Completion (context.yaml update, user notification)

---

## Task 1: Add escalation fields to context.yaml template and agent-context skill

**Files:**
- Modify: `.claude/skills/agent-context/template.yaml`
- Modify: `.claude/skills/agent-context/SKILL.md`

- [ ] **Step 1: Add escalation fields to template.yaml**

In `.claude/skills/agent-context/template.yaml`, replace the `workflow` block:

```yaml
workflow:
  current_step: define  # Active step: define | research | plan | implement | validate | document | complete
  completed_steps: []   # Ordered list of steps that have completed and handed off
  checkpoint: ""        # Free-text resume point within the current step. Set after each sub-task commit, cleared on handoff.
```

with:

```yaml
workflow:
  current_step: define  # Active step: define | research | plan | implement | validate | document | complete
  completed_steps: []   # Ordered list of steps that have completed and handed off
  checkpoint: ""        # Free-text resume point within the current step. Set after each sub-task commit, cleared on handoff.
  escalated: false      # Set to true by an agent when it cannot resolve an issue after 3 attempts
  escalation_reason: "" # Human-readable description of what caused the escalation and what was tried
```

- [ ] **Step 2: Document escalation fields in agent-context SKILL.md**

In `.claude/skills/agent-context/SKILL.md`, add a new section after the `## Documentation created registry` section (before the `## Template` section):

```markdown
## Escalation signaling

When an agent cannot resolve an issue after 3 attempts (failed tests, linter errors, code review findings that won't clear), it signals the orchestrator by writing to `context.yaml` before returning:

```yaml
workflow:
  escalated: true
  escalation_reason: |
    [Which reviewer or check is blocked]
    [What was attempted in each of the 3 iterations]
    [Assessment of root cause]
```

The agent then returns immediately — it does not notify the user directly. The workflow orchestrator reads `workflow.escalated` after each agent returns and halts the pipeline if it is `true`, surfacing `workflow.escalation_reason` to the user.
```

- [ ] **Step 3: Verify template.yaml**

Read `.claude/skills/agent-context/template.yaml` and confirm the `workflow` block contains `escalated: false` and `escalation_reason: ""`.

- [ ] **Step 4: Verify SKILL.md**

Read `.claude/skills/agent-context/SKILL.md` and confirm the escalation signaling section is present with the yaml block showing `escalated: true` and `escalation_reason`.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/agent-context/template.yaml .claude/skills/agent-context/SKILL.md
git commit -m "feat(agent-context): add escalation signaling fields to context.yaml"
```

---

## Task 2: Strip Define agent handoff

**Files:**
- Modify: `.claude/agents/define.md`

- [ ] **Step 1: Remove step 7 from the Workflow section**

In `.claude/agents/define.md`, replace step 7 in the `## Workflow` section:

```markdown
7. **Confirm with user** — before starting ANY implementation or changes, check back with the user and get confirmation before moving onto the Research step. Once confirmed:
   - Update `**Status:** Draft` to `**Status:** Approved` in `1_spec.md`.
   - Update `context.yaml`: set `workflow.current_step` to `research` and add `define` to `workflow.completed_steps`.
   - Tell the user: "Spec approved. Starting Research step."
   - Invoke the Research agent, passing `feature.folder` from `context.yaml` as the argument.
```

with:

```markdown
7. **Return** — your work is complete. The workflow orchestrator will present the spec for user approval and advance to Research.
```

- [ ] **Step 2: Update the Output section**

In `.claude/agents/define.md`, replace the `## Output` section:

```markdown
## Output

The Define step is complete when:

- A `.docs/YYYY-MM-DD-<short-name>/` folder exists with `artifacts/` and `output-artifacts/` subdirectories.
- `1_spec.md` is written, reviewed, and approved by the user.
- There are no major open questions that would block the Research step.
```

with:

```markdown
## Output

The Define step is complete when:

- A `.docs/YYYY-MM-DD-<short-name>/` folder exists with `artifacts/` and `output-artifacts/` subdirectories.
- `1_spec.md` is written and self-reviewed (no placeholders, no open ambiguities).
- The draft PR is created and pushed to remote.
- There are no major open questions that would block the Research step.
```

- [ ] **Step 3: Verify**

Read `.claude/agents/define.md` and confirm:
- Step 7 says "Return" and mentions the orchestrator
- The Output section does not mention "approved by the user"
- No mention of invoking the Research agent remains in the file

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/define.md
git commit -m "refactor(agents): remove handoff from define agent"
```

---

## Task 3: Strip Research agent handoff

**Files:**
- Modify: `.claude/agents/research.md`

- [ ] **Step 1: Remove the handoff lines from the Output section**

In `.claude/agents/research.md`, replace the end of the `## Output` section:

```markdown
Once `2_research.md` is written:

- For every file created in `artifacts/`, append an entry to the `artifacts` list in `context.yaml` with its path (relative to `feature.folder`), a description of what it is, and `created_by: research`.
- Update `context.yaml`: set `workflow.current_step` to `plan` and add `research` to `workflow.completed_steps`.
- Tell the user: "Research complete. Starting Plan step."
- Invoke the Plan agent, passing `feature.folder` as the argument.
```

with:

```markdown
Once `2_research.md` is written:

- For every file created in `artifacts/`, append an entry to the `artifacts` list in `context.yaml` with its path (relative to `feature.folder`), a description of what it is, and `created_by: research`.
```

- [ ] **Step 2: Verify**

Read `.claude/agents/research.md` and confirm:
- The Output section ends after the artifacts registry bullet
- No mention of `workflow.current_step`, `workflow.completed_steps`, Plan agent invocation, or "Research complete" announcement remains

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/research.md
git commit -m "refactor(agents): remove handoff from research agent"
```

---

## Task 4: Strip Plan agent handoff

**Files:**
- Modify: `.claude/agents/plan.md`

- [ ] **Step 1: Remove the handoff lines**

In `.claude/agents/plan.md`, replace the end of the file after the `## Plan Self-Review` section:

```markdown
Once complete, commit the plan. Then:

- Update `context.yaml`: set `workflow.current_step` to `implement` and add `plan` to `workflow.completed_steps`.
- Tell the user: "Plan complete. Starting Implementation step."
- Invoke the Implement agent, passing `feature.folder` as the argument.
```

with:

```markdown
Once complete, commit the plan.
```

- [ ] **Step 2: Verify**

Read `.claude/agents/plan.md` and confirm:
- The file ends with "Once complete, commit the plan." (or equivalent)
- No mention of `workflow.current_step`, `workflow.completed_steps`, Implement agent invocation, or "Plan complete" announcement remains

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/plan.md
git commit -m "refactor(agents): remove handoff from plan agent"
```

---

## Task 5: Update Implement agent (escalation signal + remove handoff)

**Files:**
- Modify: `.claude/agents/implement.md`

- [ ] **Step 1: Replace the Escalation section's halt instruction**

In `.claude/agents/implement.md`, replace the last paragraph of the `## Escalation` section:

```markdown
Notify the user with this summary and halt. Do not proceed to Validate.
```

with:

```markdown
Write the escalation to `context.yaml` and return:

```yaml
workflow:
  escalated: true
  escalation_reason: |
    [What is failing and the exact error]
    [What was attempted in each of the 3 attempts and why it didn't work]
    [Assessment of why this is stuck]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this to the user.
```

- [ ] **Step 2: Replace the Handoff section**

In `.claude/agents/implement.md`, replace the entire `## Handoff` section:

```markdown
## Handoff

Once all tasks are complete, the full test suite passes, and coverage is above 80%:

- Update `context.yaml`: set `workflow.current_step` to `validate` and add `implement` to `workflow.completed_steps`.
- Tell the user: "Implementation complete. Starting Validate step."
- Invoke the Validate agent, passing `feature.folder` as the argument.
```

with:

```markdown
## Completion

Once all tasks are complete, the full test suite passes, and coverage is above 80%, return. The workflow orchestrator will advance to the Validate step.
```

- [ ] **Step 3: Verify**

Read `.claude/agents/implement.md` and confirm:
- The Escalation section ends with the context.yaml yaml block and "Do not notify the user directly"
- The Handoff/Completion section does not mention invoking the Validate agent, `workflow.current_step`, or `workflow.completed_steps`

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/implement.md
git commit -m "refactor(agents): remove handoff from implement agent, signal escalation via context.yaml"
```

---

## Task 6: Update Validate agent (escalation signal + remove handoff)

**Files:**
- Modify: `.claude/agents/validate.md`

- [ ] **Step 1: Replace the Escalation section's halt instruction**

In `.claude/agents/validate.md`, replace the last paragraph of the `## Escalation` section:

```markdown
Notify the user with this summary and halt. Do not proceed to Document.
```

with:

```markdown
Write the escalation to `context.yaml` and return:

```yaml
workflow:
  escalated: true
  escalation_reason: |
    [Which reviewer is blocked and the specific unresolved findings]
    [What was attempted in each of the 3 iterations and why it didn't resolve]
    [Assessment of root cause]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this to the user.
```

- [ ] **Step 2: Remove the handoff lines from Completion**

In `.claude/agents/validate.md`, replace the end of the `## Completion` section:

```markdown
Then:

- Update `context.yaml`: set `workflow.current_step` to `document` and add `validate` to `workflow.completed_steps`.
- Tell the user: "Validation complete. Starting Document step."
- Invoke the Document agent, passing `feature.folder` as the argument.
```

with:

```markdown
Then return. The workflow orchestrator will advance to the Document step.
```

- [ ] **Step 3: Verify**

Read `.claude/agents/validate.md` and confirm:
- The Escalation section ends with the yaml block and "Do not notify the user directly"
- The Completion section ends with "Then return" and does not mention invoking the Document agent, `workflow.current_step`, or `workflow.completed_steps`

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/validate.md
git commit -m "refactor(agents): remove handoff from validate agent, signal escalation via context.yaml"
```

---

## Task 7: Strip Document agent handoff

**Files:**
- Modify: `.claude/agents/document.md`

- [ ] **Step 1: Remove steps 2 and 3 from the Completion section**

In `.claude/agents/document.md`, replace the `## Completion` section:

```markdown
## Completion

After committing all documentation updates and the PR description is written:

1. Remove the draft status with `gh pr ready`.
2. Update `context.yaml`: set `workflow.current_step` to `complete` and add `document` to `workflow.completed_steps`.
3. Notify the user that the feature implementation is complete, the PR is ready for review, and share the PR link.
```

with:

```markdown
## Completion

After committing all documentation updates and the PR description is written:

1. Remove the draft status with `gh pr ready`.
```

- [ ] **Step 2: Verify**

Read `.claude/agents/document.md` and confirm:
- The Completion section contains only the `gh pr ready` step
- No mention of `workflow.current_step`, `workflow.completed_steps`, user notification, or PR link sharing remains in the Completion section

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/document.md
git commit -m "refactor(agents): remove handoff from document agent"
```

---

## Task 8: Rewrite feature skill as pipeline orchestrator

**Files:**
- Modify: `.claude/skills/feature/SKILL.md`

- [ ] **Step 1: Replace the full content of the feature skill**

Overwrite `.claude/skills/feature/SKILL.md` with:

```markdown
---
name: feature
description: Entry point for the development workflow. Orchestrates the full pipeline from Define through Document. Start a new feature or resume an in-progress one.
argument-hint: "[feature idea or description]"
disable-model-invocation: true
---

# Feature Workflow

Orchestrates the full development pipeline: Define → Research → Plan → Implement → Validate → Document.

## Step 1: Check for in-progress workflows

Run:

```bash
find .docs -name "context.yaml" 2>/dev/null | sort
```

For each `context.yaml` found, read it and check `workflow.current_step`. A workflow is in-progress if `workflow.current_step` is not `complete`.

## Step 2: If in-progress workflows exist

List each one for the user with:
- Feature name (`feature.name`)
- Current step (`workflow.current_step`)
- Checkpoint if set (`workflow.checkpoint`)

Ask: "Do you want to resume one of these, or start a new feature?"

**To resume:** Read the `context.yaml`, set `feature_folder` to its `feature.folder` value, then jump to the step named in `workflow.current_step` in the **Pipeline** section below.

**To start new:** Continue to Step 3.

## Step 3: Start a new feature

If a feature idea was passed as `$ARGUMENTS`, use it as the starting context for the Define agent. Otherwise ask the user what they want to build first.

Announce: `"Starting Define..."`

Invoke the Define agent with the feature idea. After it returns, scan for context.yaml files again with the same `find` command. Read the one where `workflow.current_step` is `define` and `workflow.completed_steps` is empty — this is the one Define just created. Set `feature_folder` to its `feature.folder` value.

Then proceed to the **Approval Gate** below.

## Pipeline

### Post-return protocol

Run this after every agent returns:

1. Read `context.yaml` from `feature_folder`.
2. If `workflow.escalated` is `true`: halt immediately. Tell the user: `"Pipeline halted — " + workflow.escalation_reason`. Do not update `context.yaml`. Do not invoke the next agent. Stop.
3. Append the completed step name to `workflow.completed_steps`.
4. Set `workflow.current_step` to the next step name (see sequence table below).
5. Write the updated `context.yaml`.

### Approval Gate (after Define)

Before advancing to Research:

1. Read `1_spec.md` from `feature_folder`.
2. Present the **Summary** and **Acceptance Criteria** sections to the user.
3. Ask: "Does this spec look right? Approve to continue to Research, or provide feedback to revise."
4. **Approved:** run the post-return protocol (completed: `define`, next: `research`), then announce `"Spec approved. Starting Research..."` and invoke the Research agent.
5. **Feedback given:** re-invoke the Define agent with `feature_folder` as the argument and the user's feedback noted in context. Repeat the gate after Define returns (skip the post-return protocol on the revision pass — only run it on approval).

### Step sequence

| Completed step | Next step |
|---|---|
| define | research |
| research | plan |
| plan | implement |
| implement | validate |
| validate | document |
| document | complete |

After the Approval Gate, invoke each remaining agent in order. Before each invocation announce `"Starting [Step]..."`. After each returns, run the post-return protocol, announce `"[Step] complete."`, then continue.

| Step | Agent to invoke |
|---|---|
| research | Research agent |
| plan | Plan agent |
| implement | Implement agent |
| validate | Validate agent |
| document | Document agent |

Pass `feature_folder` as the argument to every agent.

### Completion

After the Document agent returns and the post-return protocol runs without escalation:

1. Read `feature.branch` from `context.yaml`.
2. Run: `gh pr view <feature.branch> --json url -q .url`
3. Announce: `"Workflow complete. PR is ready for review: [PR URL]"`
```

- [ ] **Step 2: Verify the frontmatter**

Read `.claude/skills/feature/SKILL.md` and confirm:
- `name: feature` is present
- `disable-model-invocation: true` is present
- `argument-hint` is present

- [ ] **Step 3: Verify the pipeline structure**

Confirm the file contains all of:
- A `find .docs -name "context.yaml"` command in Step 1
- A resume path that sets `feature_folder` and jumps to `workflow.current_step`
- A `$ARGUMENTS` reference in Step 3
- The post-return protocol with the `workflow.escalated` check
- The Approval Gate with both approve and feedback paths
- The step sequence table covering all 6 steps
- The completion block with `gh pr view`

- [ ] **Step 4: Verify no agent invokes a pipeline-sequencing agent**

Run:
```bash
grep -in "invoke the.*agent" .claude/agents/*.md
```

Expected output contains only:
- `implement.md` — "invoke the Code Reviewer agent" (internal sub-orchestration, keep)
- `validate.md` — "Invoke the Senior Reviewer agent" and "invoke the QA Reviewer agent" (internal sub-orchestration, keep)

Any match from `define.md`, `research.md`, `plan.md`, or `document.md` is a bug — those files must not invoke pipeline agents.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/feature/SKILL.md
git commit -m "feat(skills): rewrite feature skill as pipeline orchestrator"
```
