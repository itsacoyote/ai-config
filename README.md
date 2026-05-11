# AI Config

A Claude Code template that takes a feature from idea to production-ready PR. You define the feature. Claude does the rest.

---

## How it works in one sentence

You have a conversation with Claude to define and approve a feature spec. Once you approve, Claude runs the full pipeline autonomously — researching the codebase, writing an implementation plan, building the feature with TDD, validating it through brutal code and QA review, and documenting everything — then sends you a notification when the PR is ready.

---

## The pipeline

```
You talk to Claude
        |
        v
  [ DEFINE ]  <-- only step that requires back-and-forth with you
  Spec written,
  branch created,
  you approve
        |
        v
  [ RESEARCH ]  autonomous
  Codebase studied,
  reuse identified,
  2_research.md written
        |
        v
  [ PLAN ]  autonomous
  File map locked,
  TDD task list written,
  3_plan.md written
        |
        v
  [ IMPLEMENT ]  autonomous
  Code written task by task,
  tests pass before moving on,
  code reviewed at checkpoints
        |
        v
  [ VALIDATE ]  autonomous
  Senior engineer tears it apart,
  QA verifies real coverage,
  4_validate.md written
        |
        v
  [ DOCUMENT ]  autonomous
  Docs updated, PR description written,
  screenshots embedded,
  PR marked ready
        |
        v
  You get notified
```

---

## How to start a feature

1. Open Claude Code in your project
2. Invoke the Define agent:

```
Use the define agent — I want to build [your feature idea]
```

3. Have a conversation with Claude. It will ask clarifying questions about scope, constraints, acceptance criteria, etc.
4. When the spec looks right, tell Claude you approve it.
5. That's it. Claude runs the rest of the pipeline and notifies you when the PR is ready.

> **You only need to be present for the Define step.** Everything after your approval is autonomous.

---

## What each step does

### Define
**Who drives it:** You and Claude together.

Claude helps you think through a feature before anything gets built. It asks about the problem, goals, non-goals, user stories, constraints, and acceptance criteria. Once you're happy with the spec, you approve it. Claude then creates the feature branch, writes `1_spec.md`, and hands off to Research automatically.

### Research
**Who drives it:** Claude, autonomously.

Claude reads the approved spec and studies the codebase — looking for existing code to reuse, patterns to follow, and gaps to fill. It uses sub-skills to analyze specific files, find conventions, and look up third-party docs if needed. Results go into `2_research.md`. Hands off to Plan automatically.

### Plan
**Who drives it:** Claude, autonomously.

Claude reads the spec and research, then writes a detailed implementation plan. It maps out every file that will be created, modified, or deleted — with responsibilities and interfaces — before writing a task list. Every task has explicit test cases (written before implementation), specific implementation steps, and a commit message. No vague instructions. Results go into `3_plan.md`. Hands off to Implement automatically.

### Implement
**Who drives it:** Claude, autonomously.

Claude follows the plan task by task. For each task: write tests → confirm they fail → implement → confirm tests pass → run linter → check coverage → commit → update progress in `context.yaml`. A code reviewer agent checks the work every 300–500 lines and is always invoked for security-critical or complex code. Hands off to Validate automatically.

### Validate
**Who drives it:** Claude, autonomously.

Two reviewers run in sequence:

- **Senior Reviewer** — a brutal, no-softening review against the spec, plan, and engineering standards. Checks completeness, correctness, coherence, security, YAGNI, and code smells. Runs up to 3 fix iterations before escalating.
- **QA Reviewer** — checks real test coverage (no mock theater), maps e2e tests to every user story, and captures screenshots/recordings of the feature working. Runs up to 3 fix iterations before escalating.

Results go into `4_validate.md`. Hands off to Document automatically.

### Document
**Who drives it:** Claude, autonomously.

Claude reads the full diff and updates everything that changed: README, CLAUDE.md, feature docs, API docs, inline comments, changelog. It writes the PR description with visual evidence (screenshots embedded as images), marks the PR ready, and notifies you it's done.

---

## If the pipeline gets disrupted

Every agent reads `context.yaml` at the start of its gate. This file tracks where the workflow is, what's been completed, and where within the current step things left off.

**To resume after a disruption:**

1. Open `context.yaml` in the feature's `.docs/` folder
2. Check `workflow.current_step` — this is the step to resume at
3. Check `workflow.checkpoint` — this tells you where within that step things left off
4. Invoke that agent directly, passing the feature folder path:

```
Use the [step name] agent — feature folder is .docs/2026-05-11-my-feature
```

**Notes:**
- Research, Plan, and Document are safe to re-run from scratch — they overwrite their output cleanly
- Implement uses `workflow.checkpoint` to know which tasks are done; if checkpoint is empty, `git log` shows which task commits already landed
- Validate uses the checkpoint to know if the senior review already passed

---

## Escalation

If Claude gets stuck — same test failing after 3 attempts, same review issue after 3 fix cycles — it stops the pipeline and sends you a message explaining what's blocked and what was tried. It will not loop forever. You'll need to intervene and then re-invoke the relevant agent to continue.

---

## Key concepts

### context.yaml

Every feature has a `context.yaml` in its `.docs/` folder. It is created as the very first file when the spec is written, and every agent reads and updates it.

```yaml
feature:
  name: "My Feature"
  short_name: "my-feature"
  folder: ".docs/2026-05-11-my-feature"
  date: "2026-05-11"
  branch: "feature/my-feature"
  base_branch: "main"

workflow:
  current_step: implement
  completed_steps: [define, research, plan]
  checkpoint: "Completed tasks 1-4 of 9. Next: Task 5 - Add usePayment hook."

artifacts: []        # Research reference files (schemas, diagrams, etc.)
output_artifacts: [] # QA screenshots and recordings
documentation_created: [] # New docs created by the Document agent
```

### Agents vs skills

**Agents** handle a full workflow step. They have a gate (checks prerequisites), do their work, and hand off to the next agent. You invoke an agent when you want a step to run.

**Skills** are focused tools agents use to do specific work. You can also invoke skills directly with `/skill-name`. Skills used in this workflow:

| Skill | What it does |
|-------|-------------|
| `/spec` | Interactive spec writing — used by the Define agent |
| `/research` | Codebase analysis — used by the Research agent |
| `/plan` | Implementation plan writing — used by the Plan agent |
| `/analyze-code` | Surveys a specific file or module |
| `/find-patterns` | Identifies codebase conventions |
| `/web-search` | Looks up third-party docs with version verification |
| `/verify-completeness` | Checks spec requirements are implemented |
| `/verify-correctness` | Checks logic, error handling, and test quality |
| `/verify-coherence` | Checks design consistency and pattern conformance |

### The .docs/ folder

Each feature gets its own folder inside `.docs/`:

```
.docs/
└── YYYY-MM-DD-short-name/
    ├── context.yaml          # Workflow state — read by every agent
    ├── 1_spec.md             # Feature definition (Define)
    ├── 2_research.md         # Codebase findings (Research)
    ├── 3_plan.md             # Implementation plan (Plan)
    ├── 4_validate.md         # Validation report (Validate)
    ├── artifacts/            # Research reference files
    └── output-artifacts/     # QA screenshots and recordings
```

---

## Using this in a new project

This repo is a template. To use this workflow in a new project:

1. **Copy `.claude/` into your project root.** That's it — all the agents and skills are in there.

2. **Make sure CLAUDE.md exists in your project** and documents anything Claude needs to know about the project (conventions, structure, how to run tests, etc.). The Document agent will keep it updated as features are built.

3. **Open Claude Code** in your project directory and start with the Define agent.

> If you use GitHub repos for new projects, you can make this repo a GitHub template — every new repo created from it will include the `.claude/` folder automatically.

---

## File reference

```
.claude/
├── agents/
│   ├── define.md          # Step 1: interactive spec and branch setup
│   ├── research.md        # Step 2: codebase analysis
│   ├── plan.md            # Step 3: implementation plan
│   ├── implement.md       # Step 4: code the feature
│   ├── validate.md        # Step 5: code and QA review
│   ├── document.md        # Step 6: docs, PR description, notify
│   ├── code-reviewer.md   # Mid-implementation code review checkpoints
│   ├── senior-reviewer.md # Brutal final code review (used by Validate)
│   └── qa-reviewer.md     # Final QA and evidence capture (used by Validate)
└── skills/
    ├── spec/              # /spec — interactive spec writing
    ├── research/          # /research — codebase analysis and 2_research.md
    ├── plan/              # /plan — implementation plan and 3_plan.md
    ├── analyze-code/      # /analyze-code — file/module survey
    ├── find-patterns/     # /find-patterns — convention detection
    ├── web-search/        # /web-search — versioned third-party docs lookup
    ├── verify-completeness/ # checks spec requirements are present
    ├── verify-correctness/  # checks logic and test quality
    ├── verify-coherence/    # checks design and pattern consistency
    └── agent-context/     # documents context.yaml protocol and template
```
