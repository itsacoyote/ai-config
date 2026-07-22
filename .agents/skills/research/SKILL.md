---
name: research
description: Use when an approved feature spec needs codebase research into reuse, gaps, patterns, risks, dependencies, and architectural context before planning.
metadata:
  category: workflow
---

# Research

Analyze the codebase for a feature and present research findings.

## When NOT to use

Skip this skill for trivial changes whose affected code and risks are already obvious, or when current research findings for the same approved spec are complete and still valid. Do not use Research to compensate for an undefined feature; return to `define` first.

**Preflight (required).** Before doing any workflow work, verify beads is set up: resolve
`../../scripts/beads-preflight.sh` relative to this skill's directory and execute the resolved
absolute path. If it exits non-zero, **stop** — do not proceed without beads — and tell the user
to run the `setup-beads` skill, then retry.

If a spec is already in context, use it. Otherwise, ask the user to share their feature spec or describe what they want to research.

**Independent lenses are the mechanism.** Use the five neutral roles declared in
[`roles.json`](../../agents/roles.json); each focuses on one concern and this skill synthesizes
their reports. Follow the shared dispatch and write-policy contract in
[`isolated-worker-orchestration.md`](../../references/isolated-worker-orchestration.md).

**Harness routing.** Dispatch only from a parent that can own synthesis and beads mutations:

- **Codex:** use the matching project custom agents under `.codex/agents/`; independent read-only lenses may run in parallel.
- **Pi:** default to a dedicated Research session and persist its synthesis to the epic before moving to a fresh implementation session. For a bounded lens, invoke the matching role with `.agents/scripts/run-pi-role.sh`. This does not require a Pi subagent extension or tmux.
- **Other clients:** use their isolated-worker facility when it can load the neutral prompt and every declared skill completely; otherwise run the lens methodologies inline and sequentially.

If already inside an isolated worker that cannot create children, analyze inline rather than nesting workers.

## Fan-out: Always-on lenses

Run these three lenses on every research pass. Parallelize them only when the current harness provides independent read-only workers:

- **[`research-reuse`](../../agents/research-reuse.md)** — existing utilities, reuse opportunities, gaps, and duplication risk.
- **[`research-patterns`](../../agents/research-patterns.md)** — structural and naming conventions, architecture the implementation must match.
- **[`research-risks`](../../agents/research-risks.md)** — edge cases, failure modes, gotchas, and security-adjacent risks.

Each lens is read-only, returns structured text, and closes with a status. See [`lens-agent-contract.md`](../../references/lens-agent-contract.md) for the shared posture all lenses follow.

Dispatch each lens with:
1. The feature spec or description.
2. The relevant codebase area / file-map slice (so each lens stays in scope).
3. Any beads epic or task IDs the lens should reference with `bd show`.

## Fan-out: Conditional lenses

**[`research-libraries`](../../agents/research-libraries.md)** — spawn only when the feature involves a third-party tool, library, or external API. Pass the dependency name(s) and the feature spec.

**[`research-history`](../../agents/research-history.md)** — ask-first lens. Offer it to the user before spawning ("Do you want me to run the history lens to check for prior attempts in this area?"). Default to **skip** if the user doesn't confirm. Under supervised automation where the prompt cannot be answered, skip this lens entirely.

## Synthesis

Once all spawned lenses have returned, synthesize their reports into unified findings.

**Reconcile and dedup overlap between lenses.** The `research-reuse` and `research-patterns` lenses both read structural and utility files, so their findings will overlap. Deduplicate: if both surface the same file or pattern, consolidate into one finding with both lenses' perspectives noted. The synthesis step owns this — don't let the same file appear twice in the final output under different headings.

**Organize findings** using [template.md](template.md) as the structure (a findings outline — not a file to write). Present conversationally in this session. Don't write step-doc files.

**Risks and gotchas** (from `research-risks`) attach to the epic as advisory notes — they are **never** created as standalone beads issues. Record them on the epic with `bd comment <epic-id> --file <notes.md>` (see [`beads.md`](../../references/beads.md)).

**Gaps** (from `research-reuse`) still become beads child issues with dependencies, one per actionable gap — labelled `gap` so the Plan step can sweep them (`bd list --parent <epic-id> -l gap`). See [`beads.md`](../../references/beads.md) for the full model.

## No step-doc files

Do not write research findings to disk (no `.docs/research.md`, no `context.yaml`, no step-doc files). The conversational output in this session is the artifact. Beads is the system of record for gaps (child issues) and risk notes (epic advisory notes).

## Next step

Present the synthesized findings, then **recommend the next move and wait for an explicit go** (the step-handoff contract in `feature-workflow`):

- **Default:** `planning-and-task-breakdown` (Plan).
- **Recommend `prototype` first** when the findings surfaced a design question that's cheaper to answer with throwaway code than to plan around — an unsettled interaction model, a state shape the risks lens flagged as hard to reason about.

Do not start planning until the user picks. (Under `autorun`, proceed directly — Define and the PR are the only human gates there.)
