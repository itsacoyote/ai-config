# Pipeline Agents to Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split each pipeline step into a conversational skill (pure methodology, no pipeline coupling) and an infrastructure agent (gate checks, file I/O, context.yaml management).

**Architecture:** Every pipeline step agent retains its frontmatter exactly and gets a restructured body: gate → load context → invoke skill → post-skill file writes and context.yaml updates. Every pipeline step skill becomes a standalone conversational workflow with no references to context.yaml, feature folder paths, or pipeline state — usable directly in any conversation.

**Tech Stack:** Markdown files only — `.claude/agents/`, `.claude/skills/`, `README.md`.

---

## File map

### New files

| File | Responsibility |
|------|---------------|
| `.claude/skills/define/SKILL.md` | Collaborative spec conversation methodology — questions, approaches, design review. No file writes, no git ops. |
| `.claude/skills/implement/SKILL.md` | TDD implementation methodology — pre-setup, task loop, code review criteria, coverage, escalation. No context.yaml writes. |
| `.claude/skills/validate/SKILL.md` | Validation methodology — senior review then QA review, fix iteration coordination. No context.yaml writes. |

### Modified files

| File | Change summary |
|------|---------------|
| `.claude/skills/research/SKILL.md` | Remove `argument-hint`, remove `Write` from allowed-tools, remove file writing output section and context.yaml update. Add note to ask for spec if not in context. |
| `.claude/skills/plan/SKILL.md` | Remove `argument-hint`, remove `Write` from allowed-tools, remove file writing output section, remove Step 3 (recommended_skills context.yaml update). Add note to ask for spec/research if not in context. |
| `.claude/agents/define.md` | Replace body: gate check + invoke define skill + invoke spec skill + write `1_spec.md` + create draft PR. |
| `.claude/agents/research.md` | Replace body: gate check + load spec + invoke research skill + write `2_research.md` + update context.yaml artifacts. |
| `.claude/agents/plan.md` | Replace body: gate check + load spec and research + invoke plan skill + write `3_plan.md` + update context.yaml recommended_skills. |
| `.claude/agents/implement.md` | Replace body: gate check + load context + invoke implement skill + write context.yaml checkpoint. Remove `shadcn` from frontmatter skills and mcpServers. |
| `.claude/agents/validate.md` | Replace body: gate check + load context + invoke validate skill + write `4_validate.md` + write context.yaml escalation if needed. |
| `README.md` | Replace "Agents vs skills" table with three labelled sections: pipeline skills, reviewer agents, utility skills. |

---

## Task 1: Create define skill

**Files:**
- Create: `.claude/skills/define/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/define/SKILL.md` with the following content:

```markdown
---
name: define
description: Guide a collaborative spec conversation for a new feature. Works through scope, goals, constraints, and acceptance criteria to arrive at a clear, well-scoped design before anything gets built.
disable-model-invocation: true
allowed-tools: Read Bash(find *) Bash(git log *)
---

# Define

Help arrive at a clear, well-scoped feature spec through collaborative dialogue. If spec context is already in the conversation, build on it. If not, start from scratch with the user.

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every feature goes through this process. The conversation can be short for simple features, but you must go through it. A brief conversation is better than skipping and discovering missed requirements mid-implementation.

## The Process

**Explore context first:**

- Check files, docs, and recent commits to understand the current project state
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately and help decompose into sub-projects before continuing
- If the project is too large for a single spec, help the user identify the independent pieces, how they relate, and what order to build them. Then work through the first sub-project

**Ask clarifying questions — one at a time:**

- Prefer multiple choice when possible, open-ended when necessary
- One question per message — if a topic needs more exploration, break it into multiple messages
- Focus on: purpose, constraints, success criteria, non-goals

**Explore approaches:**

- Propose 2-3 different approaches with trade-offs
- Lead with your recommended option and explain why

**Present the design:**

- Once you understand what's being built, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200–300 words if nuanced
- Ask after each section whether it looks right
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, answer: what does it do, how do you use it, what does it depend on?
- Can someone understand a unit without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work, include targeted improvements as part of the design
- Don't propose unrelated refactoring

## Key Principles

- **One question at a time** — don't overwhelm with multiple questions
- **Multiple choice preferred** — easier to answer than open-ended when possible
- **YAGNI ruthlessly** — cut unnecessary features from all designs
- **Explore alternatives** — always propose 2-3 approaches before settling
- **Incremental validation** — present design section by section, get approval before moving on
- **Be flexible** — go back and clarify when something doesn't make sense
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/define/SKILL.md
git commit -m "feat(skills): add define skill with collaborative spec conversation methodology"
```

---

## Task 2: Refactor define agent

**Files:**
- Modify: `.claude/agents/define.md`

- [ ] **Step 1: Read the current file**

Read `.claude/agents/define.md` in full.

- [ ] **Step 2: Replace the agent body**

Keep the frontmatter exactly as-is. Replace everything after the closing `---` of the frontmatter with:

```markdown
# Define Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to use the `/feature` skill to start a new feature.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.

## Workflow

Read and follow `.claude/skills/define/SKILL.md`.

## After the workflow completes

1. Use the `spec` skill to format the agreed design into a `1_spec.md` document. Write it to `<feature.folder>/1_spec.md`.
2. Push the branch to remote with `git push -u origin <feature.branch from context.yaml>`.
3. Run `gh pr create --draft --base <feature.base_branch from context.yaml> --title "<feature name>"`. Use the `create-pr` skill for title format. Leave the PR body minimal — it will be written by the Document agent at the end of the workflow.
4. Return. The feature orchestrator will present the spec for user approval.
```

- [ ] **Step 3: Verify the result**

The file should have the original frontmatter unchanged followed by the new body above. Check that `model: opus`, `skills:`, and `mcpServers:` blocks are intact.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/define.md
git commit -m "refactor(agents): define agent delegates methodology to define skill"
```

---

## Task 3: Update research skill

**Files:**
- Modify: `.claude/skills/research/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `.claude/skills/research/SKILL.md` in full.

- [ ] **Step 2: Update the frontmatter**

Change:
```yaml
argument-hint: [feature folder path]
allowed-tools: Read Bash(find *) Bash(grep *) Bash(git log *) Bash(git show *) Bash(git blame *) Write
```

To:
```yaml
allowed-tools: Read Bash(find *) Bash(grep *) Bash(git log *) Bash(git show *) Bash(git blame *)
```

Remove the `argument-hint` line entirely. Remove `Write` from `allowed-tools`.

- [ ] **Step 3: Replace the opening instruction**

Change:
```
Analyze the codebase for the approved feature and write `2_research.md` to the feature's folder.

If a feature folder path was passed as an argument, use `$ARGUMENTS`. Otherwise, ask the user which feature folder to work in.
```

To:
```
Analyze the codebase for a feature and present research findings.

If a spec is already in context, use it. Otherwise, ask the user to share their feature spec or describe what they want to research.
```

- [ ] **Step 4: Remove the Artifacts section**

Remove this entire section:

```
## Artifacts

If you produce any artifacts during research (diagrams, data samples, reference files, exported schemas, etc.):

1. Place them in the feature's `artifacts/` folder.
2. Reference each one in `2_research.md`.
3. Append an entry for each to the `artifacts` list in `context.yaml` with its path relative to the feature folder, a description, and `created_by: research`. This makes them discoverable by all downstream agents without scanning the directory.
```

Replace it with:

```
## Artifacts

If you produce any reference files (diagrams, data samples, exported schemas, etc.) during research, note them clearly in your findings so the user or a downstream agent can save them if needed.
```

- [ ] **Step 5: Replace the Output section**

Change:
```
## Output

Write `2_research.md` in the feature's folder using the template in [template.md](template.md).
```

To:
```
## Output

Present research findings in the conversation using the structure in [template.md](template.md) as a guide. Do not write files unless the user asks.
```

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/research/SKILL.md
git commit -m "refactor(skills): make research skill conversational, remove file I/O"
```

---

## Task 4: Refactor research agent

**Files:**
- Modify: `.claude/agents/research.md`

- [ ] **Step 1: Read the current file**

Read `.claude/agents/research.md` in full.

- [ ] **Step 2: Replace the agent body**

Keep the frontmatter exactly as-is. Replace everything after the closing `---` of the frontmatter with:

```markdown
# Research Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to run the Define agent first.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.
- If `1_spec.md` does not have `**Status:** Approved`, stop. Tell the user the spec hasn't been approved yet and recommend they finish the Define step.
- Read `1_spec.md` fully before proceeding.

## Workflow

Read and follow `.claude/skills/research/SKILL.md`.

## After the workflow completes

1. Write the research findings to `<feature.folder>/2_research.md` using the template at `.claude/skills/research/template.md` as the structure.
2. For every artifact file noted during research, save it to `<feature.folder>/artifacts/` and append an entry to the `artifacts` list in `context.yaml` with its path relative to `feature.folder`, a description, and `created_by: research`.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/research.md
git commit -m "refactor(agents): research agent delegates methodology to research skill, owns file writes"
```

---

## Task 5: Update plan skill

**Files:**
- Modify: `.claude/skills/plan/SKILL.md`

- [ ] **Step 1: Read the current file**

Read `.claude/skills/plan/SKILL.md` in full.

- [ ] **Step 2: Update the frontmatter**

Change:
```yaml
argument-hint: "[feature folder path]"
allowed-tools: Read Write Bash(find *)
```

To:
```yaml
allowed-tools: Read Bash(find *)
```

Remove the `argument-hint` line entirely. Remove `Write` from `allowed-tools`.

- [ ] **Step 3: Replace the opening instruction**

Change:
```
Write `3_plan.md` for the feature in `$ARGUMENTS`. If no path is provided, ask which feature folder to plan.

Read `1_spec.md` and `2_research.md` fully before writing anything, including any artifacts referenced in the research doc.
```

To:
```
Produce an implementation plan for a feature.

If a spec and research findings are already in context, use them. Otherwise, ask the user to share the spec and any relevant research before beginning.
```

- [ ] **Step 4: Remove Step 3 (Recommend skills)**

Remove the entire `## Step 3: Recommend skills` section — everything from that heading through the closing YAML block. This responsibility moves to the plan agent.

- [ ] **Step 5: Replace the Output section**

Change:
```
## Output

Write `3_plan.md` using the template in [template.md](template.md).
```

To:
```
## Output

Present the complete implementation plan in the conversation using the structure in [template.md](template.md) as a guide. Do not write files unless the user asks.
```

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/plan/SKILL.md
git commit -m "refactor(skills): make plan skill conversational, remove file I/O and context.yaml update"
```

---

## Task 6: Refactor plan agent

**Files:**
- Modify: `.claude/agents/plan.md`

- [ ] **Step 1: Read the current file**

Read `.claude/agents/plan.md` in full.

- [ ] **Step 2: Replace the agent body**

Keep the frontmatter exactly as-is. Replace everything after the closing `---` of the frontmatter with:

```markdown
# Plan Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to run the Define agent first.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.
- If `1_spec.md` is missing, stop. Recommend the Define agent.
- If `2_research.md` is missing, stop. Recommend the Research agent.
- Read `1_spec.md` and `2_research.md` fully. Check the `artifacts` list in `context.yaml` and read any listed files — these are reference materials from Research.

## Workflow

Read and follow `.claude/skills/plan/SKILL.md`.

## After the workflow completes

1. Write the plan to `<feature.folder>/3_plan.md` using the template at `.claude/skills/plan/template.md` as the structure.
2. Scan `.claude/skills/*/SKILL.md` for locally available skills. For each, read the `name` and `description` fields from the YAML frontmatter. Exclude always-on skills: `agent-context`, `ui-design-brain`, `find-patterns`, `git-commit`. For each remaining skill, decide whether it is relevant to this feature based on `1_spec.md` and `2_research.md`. Use these heuristics:

   | Skill | Relevant when |
   |-------|---------------|
   | `security-review` | Feature involves authentication, authorization, session handling, payments, file uploads, input validation, cryptography, or SQL queries |
   | `web-search` | Feature integrates with an external API, third-party service, or library not already used in the codebase |
   | `verify-correctness` | Feature contains non-trivial algorithms, data transformations, or business logic with many edge cases |
   | `verify-coherence` | Feature spans multiple files or modules and consistency across interfaces is a risk |

   For each selected skill, write a one-line `invoke_when` hint specific to this feature. Update `recommended_skills` in `context.yaml` (preserve all other fields):

   ```yaml
   recommended_skills:
     - skill: security-review
       invoke_when: "Before implementing the JWT validation logic in Task 3"
   ```

   If no skills are relevant, write `recommended_skills: []`.
3. Commit the plan with a conventional commit message.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/plan.md
git commit -m "refactor(agents): plan agent delegates methodology to plan skill, owns file writes and skill recommendations"
```

---

## Task 7: Create implement skill

**Files:**
- Create: `.claude/skills/implement/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/implement/SKILL.md` with the following content:

```markdown
---
name: implement
description: Guide a TDD implementation from a plan document. Works through each task in order — write tests first, implement, verify, commit. Includes code review checkpoints and coverage enforcement.
disable-model-invocation: true
allowed-tools: Read Edit Write Bash(*) Agent
---

# Implement

Execute an implementation plan task by task with TDD. If no plan is in context, ask the user to share one before beginning.

The plan has already made all architecture and decomposition decisions. Follow it faithfully. If something in the plan seems wrong, stop and flag it rather than improvising.

## Pre-Implementation Setup

Before writing any code:

1. **Read every file in the plan's file map** — read the current state of each file listed under New Files and Modified Files. Do not work from memory or assumptions about what's there.
2. **Run the existing test suite** — establish a baseline. Record which tests pass, which fail, and the current coverage percentage. If tests are already failing, stop and tell the user before proceeding.
3. **Note any skill recommendations** — if the plan includes a list of skills to invoke at certain tasks, note them now. You will invoke them when those tasks are reached.

## Implementation Loop

Work through tasks in the order defined in the plan. For each task:

1. **Re-read the relevant files** — always read the current file state before editing, even if you read it during setup.
2. **Write the tests** — write exactly the test cases named in the plan. Do not add tests not in the plan; do not skip tests that are. Run them and confirm they fail for the right reason.
3. **Implement** — follow the plan's implementation steps in order. Each step names a specific function, component, route, or schema — build exactly that.
4. **Run the tests** — confirm all tests for this task pass. If any fail, fix them before moving to the next task. Do not batch and fix later.
5. **Run the linter** — run the project's linter and formatter. Fix any violations before committing. Tests passing and linter failing will still break CI.
6. **Check coverage** — coverage must not drop below 80% across unit, integration, and e2e tests. If it does, add the missing coverage before committing.
7. **Commit** — use the commit message specified in the plan.

## Code Review

Track the total lines of code generated since the last code review. After every 300–500 lines, invoke the Code Reviewer agent before continuing to the next task. Pass the plan document so the Code Reviewer can check plan alignment.

**Always invoke the Code Reviewer for:**

- Security-critical code: authentication, authorization, session handling, payment processing, input validation, file uploads, cryptography, SQL or ORM queries
- Complex algorithms: non-trivial data transformations, performance-sensitive logic, concurrency
- Large refactorings: changes that touch more than 3 files or alter a shared interface

**Optionally invoke the Code Reviewer for:**

- Test code
- Low-complexity UI components
- Simple CRUD operations

**Do not invoke the Code Reviewer for:**

- Documentation changes
- Trivial bug fixes under 10 lines
- Configuration changes

When the Code Reviewer returns issues, fix all of them before continuing. When it returns approval, reset the line count and proceed. If the Code Reviewer returns the same issues after 3 fix attempts with no meaningful progress, stop — do not attempt a 4th fix. See **Escalation** below.

## Coverage Requirements

Maintain >80% test coverage throughout implementation. Coverage applies across all test types:

- **Unit tests** — individual functions, components, and modules in isolation
- **Integration tests** — interactions between modules, API endpoints, and database operations
- **E2E tests** — full user flows through the feature as described in the spec's user stories

## Escalation

If you have made 3 full attempts to resolve the same issue — whether a failing test, a linter error, or a code review finding — without meaningful progress, stop. Do not attempt a 4th fix. Return to the user with:

- What is failing and the exact error or finding
- What was attempted in each of the 3 attempts and why it didn't work
- Your assessment of why this is stuck (architectural mismatch, missing information, ambiguity in the plan)

## Constraints

- Follow the plan exactly. Do not add, remove, or restructure beyond what it specifies.
- Never batch all changes and test at the end. Each task must pass tests before the next begins.
- Do not modify files outside the plan's file map without flagging it to the user first.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/implement/SKILL.md
git commit -m "feat(skills): add implement skill with TDD implementation methodology"
```

---

## Task 8: Refactor implement agent

**Files:**
- Modify: `.claude/agents/implement.md`

- [ ] **Step 1: Read the current file**

Read `.claude/agents/implement.md` in full.

- [ ] **Step 2: Update the frontmatter**

Remove `shadcn` from the `skills:` list and from the `mcpServers:` list. The resulting frontmatter should be:

```yaml
---
name: implement
description: Implement step agent. Follows the plan document to build the feature incrementally with TDD. Only runs if 3_plan.md exists for the feature. Use after the Plan step is complete.
model: sonnet
skills:
  - agent-context
  - ui-design-brain
  - find-patterns
  - git-commit
mcpServers:
  - github
---
```

- [ ] **Step 3: Replace the agent body**

Replace everything after the closing `---` of the frontmatter with:

```markdown
# Implement Agent

## Gate

Before doing anything else, read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs.

- If `context.yaml` is missing or no argument was passed, stop. Tell the user to start from the Define agent.
- Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.
- If `3_plan.md` is missing, stop. Recommend the Plan agent.
- Read `1_spec.md` and `3_plan.md` fully. Check the `artifacts` list in `context.yaml` and read any listed files.
- Check `workflow.checkpoint` in `context.yaml`. If set, resume from that task. If not set, start from Task 1.
- Load `recommended_skills` from `context.yaml`. Note each entry's `skill` name and `invoke_when` condition — pass these to the skill as context.

## Pre-Implementation Setup

Check whether the feature branch has a remote tracking branch:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

If it does, run `git pull`. If it does not (branch is local only), skip — nothing to pull. If there are merge conflicts, stop and resolve them with the user before proceeding.

## Workflow

Read and follow `.claude/skills/implement/SKILL.md`.

The `recommended_skills` loaded above are the skill recommendations for this feature. When the implement skill says "note any skill recommendations," these are them — apply the `invoke_when` conditions as you work through tasks.

## After each task completes

Write a brief `workflow.checkpoint` to `context.yaml` noting which task just completed and what comes next. Example: `"Completed tasks 1-3 of 7. Next: Task 4 - Add useAuthToken hook."` Preserve all other fields.

## If the skill cannot complete

If the implement skill signals it cannot resolve an issue after 3 attempts, write the escalation to `context.yaml` and return:

```yaml
# Merge into existing workflow block — do not replace other fields
workflow:
  escalated: true
  escalation_reason: |
    [What is failing and the exact error]
    [What was attempted in each of the 3 attempts and why it didn't work]
    [Assessment of why this is stuck]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/implement.md
git commit -m "refactor(agents): implement agent delegates methodology to implement skill, remove shadcn"
```

---

## Task 9: Create validate skill

**Files:**
- Create: `.claude/skills/validate/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/validate/SKILL.md` with the following content:

```markdown
---
name: validate
description: Coordinate a senior code review followed by a QA review. Runs both reviewers in sequence, manages fix iterations between rounds, and produces a validation summary. Use after implementation is complete.
disable-model-invocation: true
allowed-tools: Read Bash(*) Agent
---

# Validate

Run a senior code review followed by a QA review. Fix issues and repeat until both reviewers pass.

If feature context (spec, plan, diff) isn't already in the conversation, ask the user to share what was implemented before beginning.

This is the last gate before code ships. Do not soften findings, rush approvals, or skip steps because the implementation looks mostly fine.

## Validation Loop

Run both reviewers in order. Do not advance to the next reviewer until the current one passes.

### Round 1 — Senior Code Review

Invoke the Senior Reviewer agent. Pass the spec, plan, and full diff as context.

If the Senior Reviewer returns issues:

1. Fix each issue exactly as specified — do not interpret or improvise on the fix.
2. Run the test suite after fixes to confirm nothing broke.
3. Commit the fixes.
4. Re-invoke the Senior Reviewer.
5. Repeat until the Senior Reviewer approves, up to a maximum of 3 fix iterations.

If the same issues persist after 3 attempts, stop. Return a clear summary of:
- Which issues remain unresolved
- What was attempted in each iteration and why it didn't work
- Your assessment of the root cause

Do not attempt further fixes.

### Round 2 — QA Review

Once the Senior Reviewer has approved, invoke the QA Reviewer agent.

If the QA Reviewer returns issues:

1. Fix each issue exactly as specified.
2. Run the full test suite and verify coverage stays above 80%.
3. Commit the fixes.
4. Re-invoke the QA Reviewer.
5. Repeat until the QA Reviewer approves, up to a maximum of 3 fix iterations.

If the same issues persist after 3 attempts, stop. Return a clear summary as above.

## Completion

Once both reviewers have approved, produce a validation summary with:

- Senior review verdict and number of fix iterations
- QA review verdict, coverage achieved, and number of fix iterations
- For each finding that required fixing: what the finding was and what changed to resolve it
- A list of evidence artifacts captured by the QA Reviewer
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/validate/SKILL.md
git commit -m "feat(skills): add validate skill with review coordination methodology"
```

---

## Task 10: Refactor validate agent

**Files:**
- Modify: `.claude/agents/validate.md`

- [ ] **Step 1: Read the current file**

Read `.claude/agents/validate.md` in full.

- [ ] **Step 2: Replace the agent body**

Keep the frontmatter exactly as-is. Replace everything after the closing `---` of the frontmatter with:

```markdown
# Validate Agent

## Gate

Before doing anything:

1. Read `context.yaml` from the feature folder passed as your argument. Use `feature.folder` to locate all docs. If missing, stop and tell the user to start from the Define agent.
2. Verify you are on the correct branch: compare `git rev-parse --abbrev-ref HEAD` to `feature.branch` in `context.yaml`. If they differ, run `git checkout <feature.branch>`. If the branch doesn't exist locally, run `git checkout -b <feature.branch> origin/<feature.branch>`. If checkout fails, stop and notify the user.
3. Check that `3_plan.md` exists. If not, stop — the Plan step wasn't completed.
4. Run `BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'); git diff $(git merge-base HEAD ${BASE:-main}) HEAD --stat` to confirm there are changes to review. If there's no diff, stop and tell the user there's nothing to validate.
5. Read `1_spec.md`, `2_research.md`, and `3_plan.md` fully.

## Workflow

Read and follow `.claude/skills/validate/SKILL.md`.

## After the workflow completes

Write `4_validate.md` to `<feature.folder>` with this structure:

```markdown
# Validation: <Feature Name>

**Date:** YYYY-MM-DD
**Spec:** [1_spec.md](1_spec.md)

## Senior Code Review

**Verdict:** Approved
**Iterations:** N

### Findings and fixes

- [Finding] → [What was changed to resolve it]

## QA Review

**Verdict:** Approved
**Coverage achieved:** N%
**Iterations:** N

### Findings and fixes

- [Finding] → [What was changed to resolve it]

## Evidence

List each entry from `output_artifacts` in `context.yaml` with its description and the user story it demonstrates.
```

## If the skill cannot complete

If the validate skill signals it cannot resolve an issue after 3 attempts, write the escalation to `context.yaml` and return:

```yaml
# Merge into existing workflow block — do not replace other fields
workflow:
  escalated: true
  escalation_reason: |
    [Which reviewer is blocked and the specific unresolved findings]
    [What was attempted in each of the 3 iterations and why it didn't resolve]
    [Assessment of root cause]
```

Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/validate.md
git commit -m "refactor(agents): validate agent delegates methodology to validate skill, owns 4_validate.md write"
```

---

## Task 11: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current file**

Read `README.md` in full.

- [ ] **Step 2: Locate the "Agents vs skills" section**

Find the `### Agents vs skills` section (currently inside `## Key concepts`). It contains a table of skills with `| Skill | What it does |` headers.

- [ ] **Step 3: Replace the "Agents vs skills" section**

Replace the entire `### Agents vs skills` section (heading + table + any explanatory text) with:

```markdown
### Pipeline skills

Skills for the `Define → Research → Plan → Implement → Validate` sequence. Run automatically via `/feature`, or invoke any step directly in a conversation.

| Step | Skill | What it does |
|------|-------|--------------|
| Define | `/define` | Collaborative spec conversation — scope, goals, constraints, acceptance criteria |
| Research | `/research` | Codebase analysis for a feature — reuse, gaps, patterns, constraints |
| Plan | `/plan` | File map and TDD task list for a feature |
| Implement | `/implement` | TDD implementation guidance — task loop, code review, coverage |
| Validate | `/validate` | Senior code review then QA review coordination |

### Reviewer agents

Expert personas invoked during the pipeline. Can also be invoked directly for a focused review session.

| Agent | What it does |
|-------|--------------|
| `code-reviewer` | Mid-implementation plan alignment and quality checks (invoked by Implement) |
| `senior-reviewer` | Brutal final code review against spec, plan, and engineering standards |
| `qa-reviewer` | Coverage audit, test quality, e2e gaps, and evidence capture |

### Utility skills

Used by the pipeline internally. Also available for direct invocation outside a full pipeline run.

| Skill | What it does |
|-------|--------------|
| `/analyze-code` | Survey a file or module — structure, dependencies, behavior |
| `/find-patterns` | Identify conventions, naming patterns, and architectural decisions |
| `/web-search` | Look up versioned third-party docs and external APIs |
| `/verify-completeness` | Check spec requirements are present in the implementation |
| `/verify-correctness` | Check logic, error handling, edge cases, and test quality |
| `/verify-coherence` | Check design consistency and pattern conformance across files |
| `/security-review` | Security audit — auth, input validation, injection vectors, secrets |
| `/ui-design-brain` | UI design planning and component patterns |
```

- [ ] **Step 4: Update the file reference section**

Find the `## File reference` section. Update the `agents/` and `skills/` listings to match the new structure:

```
.claude/
├── agents/
│   ├── define.md          # Step 1: gate check, invokes define skill, writes 1_spec.md
│   ├── research.md        # Step 2: gate check, invokes research skill, writes 2_research.md
│   ├── plan.md            # Step 3: gate check, invokes plan skill, writes 3_plan.md
│   ├── implement.md       # Step 4: gate check, invokes implement skill, manages checkpoint
│   ├── validate.md        # Step 5: gate check, invokes validate skill, writes 4_validate.md
│   ├── document.md        # Step 6: docs, PR description, notify
│   ├── onboard.md         # Standalone: codebase exploration for new developers
│   ├── code-reviewer.md   # Mid-implementation code review checkpoints
│   ├── senior-reviewer.md # Brutal final code review (used by validate skill)
│   └── qa-reviewer.md     # Final QA and evidence capture (used by validate skill)
└── skills/
    ├── feature/           # /feature — pipeline orchestrator entry point
    ├── define/            # /define — collaborative spec conversation
    ├── research/          # /research — codebase analysis methodology
    ├── plan/              # /plan — implementation planning methodology
    ├── implement/         # /implement — TDD implementation methodology
    ├── validate/          # /validate — review coordination methodology
    ├── spec/              # /spec — spec document formatting (used by define agent)
    ├── analyze-code/      # /analyze-code — file/module survey
    ├── find-patterns/     # /find-patterns — convention detection
    ├── web-search/        # /web-search — versioned third-party docs lookup
    ├── verify-completeness/ # checks spec requirements are present
    ├── verify-correctness/  # checks logic and test quality
    ├── verify-coherence/    # checks design and pattern consistency
    ├── security-review/   # security audit
    ├── ui-design-brain/   # UI design planning
    └── agent-context/     # documents context.yaml protocol and template
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): restructure skills and agents reference into pipeline skills, reviewer agents, and utility skills"
```

---

## Self-review checklist

- [x] **Spec coverage:** All acceptance criteria from the spec have a corresponding task: define skill (Task 1), define agent refactor (Task 2), research skill (Task 3), research agent (Task 4), plan skill (Task 5), plan agent (Task 6), implement skill (Task 7), implement agent (Task 8), validate skill (Task 9), validate agent (Task 10), README (Task 11). shadcn removed in Task 8.
- [x] **Placeholder scan:** All task steps contain complete file content. No TBDs.
- [x] **Type consistency:** All references to skill file paths use the same form (`.claude/skills/<name>/SKILL.md`). Agent body structure is consistent across Tasks 2, 4, 6, 8, 10.
