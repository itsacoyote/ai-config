# 2. Research fans out to parallel lens subagents

Date: 2026-06-30

Status: Accepted

Tracking: beads epic (this feature)

## Context

The `research` skill ran entirely in a single context. Its `allowed-tools` was
`Read` plus a few read-only `Bash` git/grep commands — notably **no `Agent`
tool** — so it could not delegate. One context carried four distinct analysis
jobs at once (reusable code, gaps, patterns/conventions, architectural context)
and leaned on supporting skills (`analyze-code`, `find-patterns`, `web-search`)
invoked inline in the same conversation.

That single-context shape has two costs:

- **Diluted focus.** One pass juggling four questions does each less thoroughly
  than a dedicated pass per question.
- **Context bloat.** All the heavy file-reading happens in the same context that
  must then synthesize and converse, crowding out the synthesis.

The `validate` step already solves the analogous problem by fanning out to
independent agents (`senior-review`, `security-scan`, `design-review`,
`qa-review`) from the main session, then synthesizing. Research had no
equivalent, and there was no lens for **risks/gotchas** — awareness notes a
developer would flag ("this path is security-sensitive", "honor this business
rule", "this bites if missed") — anywhere in the workflow.

## Decision

`research` becomes an **orchestrator + synthesizer**. On every run it fans out to
focused, read-only **lens subagents** in parallel, then weaves their reports into
the conversational findings and the beads epic.

- **Three always-on lenses:**
  - **Reuse & gaps** — what exists to reuse/extend and what is missing (wraps the
    existing `analyze-code` skill).
  - **Patterns & architecture** — how the codebase builds similar things and how
    the layers connect (wraps the existing `find-patterns` skill).
  - **Risks & gotchas** — awareness notes that affect implementation or decisions
    (wraps a **new** `edge-cases-and-risks` skill).
- **Two conditional lenses:**
  - **Outside libraries** — fires only when the feature uses a third-party
    tool/API (wraps the existing `web-search` skill).
  - **Prior art / history** — research **asks the user first** ("check how
    similar features were built before?") and runs it only on a yes; uses git
    history (wraps `git-workflow-and-versioning`'s history guidance). In
    unattended `autorun`, the prompt cannot be answered, so this lens is
    **skipped by default**.
- Each lens is a **thin agent** wrapping a skill, per the repo convention that
  methodology lives in skills.
- The fan-out happens **from the main session (or `autorun`)** — never from a
  subagent, because subagents cannot spawn subagents. `autorun` already composes
  `research` by reading its `SKILL.md` and following it, so it spawns the lens
  agents itself.
- `research`'s `allowed-tools` gains `Agent` so a manual `/research` run can spawn
  the lenses.
- **Output mapping:** each lens fills its section of the findings template. Gaps
  still become beads child issues (unchanged). Risks/gotchas land as an advisory
  **"Risks & Gotchas"** section attached to the epic with the findings — never
  standalone issues, because they are awareness notes, not tracked work.

## Cross-harness applicability

The lens decision still applies, but dispatch follows each harness's isolation model:

- **Claude Code:** the main session fans out through the existing thin `.claude/agents/` subagents.
- **Codex:** the parent dispatches the corresponding read-only custom agents under `.codex/agents/`; the neutral role inventory remains `.agents/agents/roles.json`.
- **Pi:** the default is a dedicated Research session whose synthesized artifact is persisted to the beads epic before implementation starts. Bounded lenses may run as fresh `.agents/scripts/run-pi-role.sh` processes. Pi does not require a subagent extension or tmux, and workers cannot recursively fan out.

Unsupported clients run the portable lens methodologies inline and must still persist one synthesis. Across all harnesses, the parent owns beads mutation and synthesis; lens workers remain read-only.

## Consequences

**Positive**

- Each analysis question gets a dedicated, deeper pass; the main context stays
  lean for synthesis and conversation.
- Adds a risks/gotchas lens the workflow never had, persisted on the epic so it
  travels into Plan and Implement.
- Mirrors the proven `validate` fan-out pattern, so the codebase has one
  consistent "step orchestrates independent agents" shape.

**Negative / trade-offs**

- Every Research run now spawns multiple subagents — more tokens and some
  latency, even on small features. The conditional lenses (outside-libraries
  auto-gated, prior-art ask-first) limit the blast radius.
- More files to maintain (one new skill, several thin agents) and overlapping
  file reads across lenses that synthesis must reconcile.

## Alternatives considered

- **Keep the single broad "study the code" helper (plus risks).** Rejected: the
  maintainer explicitly wanted a robust split, and one helper juggling four jobs
  is exactly the dilution this change removes.
- **Split patterns and architecture into separate always-on lenses (four core).**
  Considered and offered; the maintainer chose to merge them into one
  "how it's built" lens to keep three core helpers.
- **Make risks/gotchas spawn beads child issues.** Rejected: they are awareness
  notes that are often not actionable on their own; forcing them into tasks
  creates fake work. They live on the epic with the findings instead.
- **Put lens methodology inline in the agent files.** Rejected: breaks the repo
  convention that methodology lives in skills and makes the lenses non-reusable.
