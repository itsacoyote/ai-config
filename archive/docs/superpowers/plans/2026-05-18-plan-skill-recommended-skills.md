# Plan Skill — Recommended Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a step to the Plan skill that scans local skills, selects relevant ones for the feature, and writes them to `context.yaml` so the Implement agent knows which skills to invoke and when.

**Architecture:** Four file edits — `context.yaml` template and its docs get the new field definition; the plan skill gets a new Step 3 that populates it; the implement agent gets a pre-implementation setup step that reads it and a loop check that acts on it.

**Tech Stack:** Markdown, YAML

---

## File Map

| File | Change |
|------|--------|
| `.claude/skills/agent-context/template.yaml` | Add `recommended_skills` block |
| `.claude/skills/agent-context/SKILL.md` | Add `## Recommended skills` registry section |
| `.claude/skills/plan/SKILL.md` | Add `## Step 3: Recommend skills` |
| `.claude/agents/implement.md` | Add step to pre-implementation setup; add check to implementation loop |

---

## Task 1: Add `recommended_skills` to context.yaml template

**Files:**
- Modify: `.claude/skills/agent-context/template.yaml`

- [ ] **Step 1: Read the current template**

Open `.claude/skills/agent-context/template.yaml` and locate the `artifacts: []` block (around line 20).

- [ ] **Step 2: Insert `recommended_skills` block after `artifacts`**

After the closing comment of the `artifacts` block (after line 34, before `output_artifacts: []`), insert:

```yaml
recommended_skills: []
# Skills the Plan agent determined are relevant for this feature's implementation.
# Populated during the Plan step. Read by the Implement agent before the implementation loop.
# Example entry:
# - skill: security-review
#   invoke_when: "After any task involving authentication, authorization, or input validation"

```

The full resulting section should read:

```yaml
artifacts: []
# Each entry describes a file created in the feature's artifacts/ folder.
# Populated by Research (and any later step that creates an artifact).
# Example entry:
# - path: artifacts/schema.png
#   description: ER diagram of the new tables added for this feature
#   created_by: research

recommended_skills: []
# Skills the Plan agent determined are relevant for this feature's implementation.
# Populated during the Plan step. Read by the Implement agent before the implementation loop.
# Example entry:
# - skill: security-review
#   invoke_when: "After any task involving authentication, authorization, or input validation"

output_artifacts: []
```

- [ ] **Step 3: Verify the edit**

Read back the file and confirm `recommended_skills: []` appears between `artifacts` and `output_artifacts`, with the comment block intact.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/agent-context/template.yaml
git commit -m "feat(agent-context): add recommended_skills field to context.yaml template"
```

---

## Task 2: Document `recommended_skills` in agent-context/SKILL.md

**Files:**
- Modify: `.claude/skills/agent-context/SKILL.md`

- [ ] **Step 1: Read the current SKILL.md**

Open `.claude/skills/agent-context/SKILL.md` and locate the `## Documentation created registry` section and the `## Escalation signaling` section that follows it.

- [ ] **Step 2: Insert `## Recommended skills` section between them**

After the closing block of `## Documentation created registry` (the `created_by: document` comment line and the closing backtick fence), insert the following new section before `## Escalation signaling`:

```markdown
## Recommended skills registry

The `recommended_skills` list is written by the Plan agent after `3_plan.md` is complete. It contains the skills the Plan agent determined are relevant for this specific feature's implementation, along with a one-line hint for when each skill should be invoked.

```yaml
- skill: security-review
  invoke_when: "After any task involving authentication, authorization, or input validation"
```

**Lifecycle:** Written by Plan. Read by Implement during pre-implementation setup. Not updated by any later step — it reflects what the Plan agent decided, not runtime events.

**Excluded:** Skills already always-on in the Implement agent's frontmatter (`agent-context`, `ui-design-brain`, `shadcn`, `find-patterns`, `git-commit`) are never added to this list — they are unconditionally available and do not need conditional recommendations.

```

- [ ] **Step 3: Verify the edit**

Read back the file and confirm the new section appears between `## Documentation created registry` and `## Escalation signaling`.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/agent-context/SKILL.md
git commit -m "docs(agent-context): document recommended_skills registry"
```

---

## Task 3: Add Step 3 to plan/SKILL.md

**Files:**
- Modify: `.claude/skills/plan/SKILL.md`

- [ ] **Step 1: Read the current plan/SKILL.md**

Open `.claude/skills/plan/SKILL.md` and locate the `## Output` section near the bottom.

- [ ] **Step 2: Insert `## Step 3: Recommend skills` before `## Output`**

Insert the following section immediately before `## Output`:

```markdown
## Step 3: Recommend skills

After writing `3_plan.md`, scan `.claude/skills/*/SKILL.md` to build a list of locally available skills. For each file, read the `name` and `description` fields from the YAML frontmatter.

Exclude skills that are already always-on in the Implement agent's frontmatter and need no conditional recommendation:
- `agent-context`
- `ui-design-brain`
- `shadcn`
- `find-patterns`
- `git-commit`

For each remaining skill, decide whether it is relevant to this feature by comparing its `description` against what you know from `1_spec.md` and `2_research.md`. Use these heuristics as a starting point:

| Skill | Relevant when |
|-------|---------------|
| `security-review` | Feature involves authentication, authorization, session handling, payments, file uploads, input validation, cryptography, or SQL queries |
| `web-search` | Feature integrates with an external API, third-party service, or library not already used in the codebase |
| `analyze-code` | Feature touches a large or unfamiliar area of the codebase not covered in research |
| `verify-correctness` | Feature contains non-trivial algorithms, data transformations, or business logic with many edge cases |
| `verify-coherence` | Feature spans multiple files or modules and consistency across interfaces is a risk |

For each selected skill, write a one-line `invoke_when` hint that is specific to this feature (not generic — reference the actual tasks or code areas from the plan).

Write the result to `context.yaml` in the feature folder:

```yaml
recommended_skills:
  - skill: security-review
    invoke_when: "Before implementing the JWT validation logic in Task 3 and the role-check middleware in Task 5"
```

If no local skills are relevant beyond the always-on set, write `recommended_skills: []` to make the absence explicit.

```

- [ ] **Step 3: Verify the edit**

Read back the file and confirm `## Step 3: Recommend skills` appears between `## Step 2: Write tasks` and `## Output`.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/plan/SKILL.md
git commit -m "feat(plan): add step to recommend skills for implement agent"
```

---

## Task 4: Update implement.md to read and act on recommended skills

**Files:**
- Modify: `.claude/agents/implement.md`

- [ ] **Step 1: Read the current implement.md**

Open `.claude/agents/implement.md` and locate:
1. The `## Pre-Implementation Setup` section — it currently has 3 numbered steps ending with "Run the existing test suite".
2. The `## Implementation Loop` section — it starts with "Work through tasks in the order defined in the plan. For each task:" and lists steps 1–8.

- [ ] **Step 2: Add step 4 to Pre-Implementation Setup**

After step 3 ("**Run the existing test suite**" paragraph), insert:

```markdown
4. **Load recommended skills** — read `recommended_skills` from `context.yaml`. If the list is non-empty, internalize each entry's `skill` name and `invoke_when` condition. You will check these at the start of each task in the implementation loop.
```

- [ ] **Step 3: Add skill check as step 1 in the Implementation Loop**

The current implementation loop step 1 is "**Re-read the relevant files**". Renumber the existing steps 1–8 to 2–9 and insert a new step 1:

```markdown
1. **Check recommended skills** — for each entry in `recommended_skills`, evaluate the `invoke_when` condition against the current task name and description. If it matches, invoke that skill now before writing any tests or code. A skill may match multiple tasks — invoke it each time the condition is met.
```

So the loop becomes:
1. Check recommended skills
2. Re-read the relevant files (was 1)
3. Write the tests (was 2)
4. Implement (was 3)
5. Run the tests (was 4)
6. Run the linter (was 5)
7. Check coverage (was 6)
8. Commit (was 7)
9. Update checkpoint (was 8)

- [ ] **Step 4: Verify the edit**

Read back the file and confirm:
- Pre-Implementation Setup has 4 steps
- Implementation Loop has 9 steps with "Check recommended skills" as step 1

- [ ] **Step 5: Commit**

```bash
git add .claude/agents/implement.md
git commit -m "feat(implement): load and act on recommended skills from context.yaml"
```

---

## Out of Scope

- Adding `recommend-when` frontmatter to individual skill files
- Dynamic modification of the implement agent's `skills:` frontmatter
- Recommendations for steps other than Implement
- Updating existing `context.yaml` files for in-progress features
