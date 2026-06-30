---
name: research
description: Analyze the codebase for a feature and present research findings conversationally — reusable code, gaps, patterns, risks, and architectural context. Works standalone or as a pipeline step.
allowed-tools: Read Bash(sh ${CLAUDE_SKILL_DIR}/../../references/beads-preflight.sh*) Bash(find *) Bash(grep *) Bash(git log *) Bash(git show *) Bash(git blame *) Bash(bd *) Agent
disable-model-invocation: true
---

# Research

Analyze the codebase for a feature and present research findings.

If a spec is already in context, use it. Otherwise, ask the user to share their feature spec or describe what they want to research.

**Fan-out is the mechanism.** This skill orchestrates parallel read-only lens agents rather than doing all analysis in a single context. Each lens focuses on one concern; this skill synthesizes their reports into a unified finding set.

**Session constraint.** The fan-out (spawning lens agents via the Agent tool) runs only from the **main session** or from **autorun**. Subagents cannot spawn subagents, so if you are running inside a subagent context, analyze inline instead — the lens agents' methodology is documented in their agent files and in the skills they load. Autorun composes this skill by reading and following it directly (it can't invoke a `disable-model-invocation` skill via the Skill tool), so autorun spawns the lenses from its own context.

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`sh ${CLAUDE_SKILL_DIR}/../../references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

## Fan-out: Always-on lenses

Spawn these three lenses **in parallel** on every run (one `Agent(...)` call per lens, all sent in the same message):

- **[`research-reuse`](../../agents/research-reuse.md)** — existing utilities, reuse opportunities, gaps, and duplication risk.
- **[`research-patterns`](../../agents/research-patterns.md)** — structural and naming conventions, architecture the implementation must match.
- **[`research-risks`](../../agents/research-risks.md)** — edge cases, failure modes, gotchas, and security-adjacent risks.

Each lens is read-only, returns structured text, and closes with a status. See [`.claude/references/lens-agent-contract.md`](../../references/lens-agent-contract.md) for the shared posture all lenses follow.

Dispatch each lens with:
1. The feature spec or description.
2. The relevant codebase area / file-map slice (so each lens stays in scope).
3. Any beads epic or task IDs the lens should reference with `bd show`.

## Fan-out: Conditional lenses

**[`research-libraries`](../../agents/research-libraries.md)** — spawn only when the feature involves a third-party tool, library, or external API. Pass the dependency name(s) and the feature spec.

**[`research-history`](../../agents/research-history.md)** — ask-first lens. Offer it to the user before spawning ("Do you want me to run the history lens to check for prior attempts in this area?"). Default to **skip** if the user doesn't confirm. Under autorun (unattended — the prompt can't be answered), skip this lens entirely.

## Synthesis

Once all spawned lenses have returned, synthesize their reports into unified findings.

**Reconcile and dedup overlap between lenses.** The `research-reuse` and `research-patterns` lenses both read structural and utility files, so their findings will overlap. Deduplicate: if both surface the same file or pattern, consolidate into one finding with both lenses' perspectives noted. The synthesis step owns this — don't let the same file appear twice in the final output under different headings.

**Organize findings** using [template.md](template.md) as the structure (a findings outline — not a file to write). Present conversationally in this session. Don't write step-doc files.

**Risks and gotchas** (from `research-risks`) attach to the epic as advisory notes — they are **never** created as standalone beads issues. Record them on the epic with `bd comment <epic-id> --file <notes.md>` (see [`.claude/references/beads.md`](../../references/beads.md)).

**Gaps** (from `research-reuse`) still become beads child issues with dependencies, one per actionable gap. See [`.claude/references/beads.md`](../../references/beads.md) for the full model.

## No step-doc files

Do not write research findings to disk (no `.docs/research.md`, no `context.yaml`, no step-doc files). The conversational output in this session is the artifact. Beads is the system of record for gaps (child issues) and risk notes (epic advisory notes).

## Next step

Hand the findings to `planning-and-task-breakdown` (Plan). See `feature-workflow` for the full sequence.
