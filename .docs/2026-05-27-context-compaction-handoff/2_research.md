# Research: Context compaction handoff

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-05-27

## Summary

This research scopes the exact edits required to add `workflow.summary` to `context.yaml`, instruct every pipeline agent to write that summary before returning and read it first on entry, and wire `/compact` into the `/feature` orchestrator's post-return protocol. The changes are confined to nine files: six agent definitions in `.claude/agents/`, two files in `.claude/skills/agent-context/`, and one orchestrator file at `.claude/skills/feature/SKILL.md`. No source code, no business logic, no tests — every file in scope is a markdown or YAML instruction document for Claude Code agents.

The repo is the agent configuration itself, so "patterns to follow" are markdown conventions used across the existing agent files. The change is mechanical and high-coverage: the same insert appears six times across the agents (with light role-specific wording), and a single block change lands in each of the three skill/orchestrator files. The biggest research finding is a design nuance worth surfacing to the Planner: subagents (the agents in `.claude/agents/`) already run in their own context windows — only their final return message lands in the orchestrator's context. So `/compact` reclaims orchestrator-side context spent on its own pre- and post-handoff bookkeeping, the Approval Gate dialogue, and what it reads itself (not anything the agents read). The `workflow.summary` field exists to solve the *downstream agent's* cold-start problem, which is the separate half of the same goal.

## Codebase Areas Affected

- `.claude/agents/define.md` — Define agent: add "write summary before returning" step. No gate change (Define is the first step and has no prior summary to read).
- `.claude/agents/research.md` — Research agent: add "write summary" step and add gate line directing it to read `workflow.summary` first.
- `.claude/agents/plan.md` — Plan agent: same two changes as Research.
- `.claude/agents/implement.md` — Implement agent: same two changes; the summary write fits into the "After all tasks complete" block alongside the final commit/push.
- `.claude/agents/validate.md` — Validate agent: same two changes.
- `.claude/agents/document.md` — Document agent: add summary write before the documentation commit (the last step before `complete`). Add gate line directing it to read `workflow.summary` first.
- `.claude/skills/feature/SKILL.md` — Orchestrator: add `/compact` invocation as step 8 of the **Post-return protocol**, after push succeeds, with explicit "do not run on escalation halt" wording (already covered by the existing halt-on-`escalated` step 2, but worth being explicit).
- `.claude/skills/agent-context/SKILL.md` — Agent context protocol doc: add a new "Workflow summary" section documenting field purpose, shape, three required content areas, lifecycle, who writes it, who reads it.
- `.claude/skills/agent-context/template.yaml` — `context.yaml` template: add `summary: ""` to the `workflow` block with a one-line inline comment, plus an example multi-line block scalar in a comment block for shape guidance.

## Reusable Code

There is no application code here — the repo is agent configuration. What's "reusable" is the consistent markdown structure already used across the six agent files. The Planner and Implementer should mimic these existing patterns rather than invent new ones.

### Patterns directly reused

- **Gate section format** — every agent has a `## Gate` section with a numbered or bulleted list of preconditions. The new "read `workflow.summary` first" line slots into this list as a bullet (Research/Plan/Validate/Document use bullets; Implement and Validate use numbered lists — match whichever the file already uses).
- **"After ..." section format** — every agent has a closing section (`## After the workflow completes`, `## After all tasks complete`, or `## Commit and push documentation`) listing a numbered sequence of steps that ends with commit + push. The new "write `workflow.summary`" step slots in as a numbered step *before* the commit step, so the summary is captured in the same commit as the step doc.
- **YAML block scalar pattern in `context.yaml`** — `escalation_reason` already uses `|` block scalar style. The in-flight `.docs/2026-05-27-context-compaction-handoff/context.yaml` further demonstrates exactly the shape `workflow.summary` will take (multi-line, prose, 300–500 tokens, three sections). The template can lift its example comment from this in-flight file.
- **`Skill(git-commit)` invocation pattern** — every agent's commit step says "Invoke `Skill(git-commit)` first, then stage and commit only those files". No new commit is introduced (the summary write folds into the existing per-step commit), so this pattern just continues to apply.

### Files exhibiting these patterns (concrete examples)

- Gate bullets: `.claude/agents/research.md:18-25`, `.claude/agents/plan.md:14-22`
- Gate numbered list: `.claude/agents/validate.md:13-20`, `.claude/agents/document.md:18-25`
- After-workflow numbered step list ending in commit + push: `.claude/agents/research.md:32-43`, `.claude/agents/plan.md:28-57`, `.claude/agents/define.md:25-38`
- YAML block scalar in `context.yaml`: `.claude/agents/research.md:49-56` (the escalation example), and the in-flight `.docs/2026-05-27-context-compaction-handoff/context.yaml:19-67` (the Define-written `workflow.summary`).
- Post-return protocol structure: `.claude/skills/feature/SKILL.md:55-73`.

## Gaps: What Needs to Be Created

- **`workflow.summary` field in the template** — does not exist in `.claude/skills/agent-context/template.yaml`. Default value is the empty string, matching how `checkpoint`, `escalation_reason`, and other free-text fields are declared.
- **"Workflow summary" section in `agent-context/SKILL.md`** — no comparable section exists. The closest analog is the existing "Artifacts registry" / "Output artifacts registry" / "Documentation created registry" sections, which all follow a consistent structure: heading, one-paragraph purpose, code-fence YAML example, lifecycle note. Mimic that structure for the new section.
- **Per-agent summary-write instruction** — does not exist in any agent. Six near-identical inserts, one per agent, varying only in: (a) role-specific wording for what "this step's outcome" means and (b) which "after" section to slot into (the agents use different headings).
- **Per-agent gate read of `workflow.summary`** — does not exist in any agent. Define is the only agent that does NOT get this gate line (it has no prior summary to read). The other five (Research, Plan, Implement, Validate, Document) get an identical line directing them to read `workflow.summary` as the primary handoff narrative, with prior step docs read on demand only.
- **`/compact` invocation in the post-return protocol** — does not exist in `.claude/skills/feature/SKILL.md`. New step 8 in the post-return protocol, placed after the push. The existing step 2 already halts on `workflow.escalated: true` before reaching the new step, so the "do not compact on escalation" requirement is satisfied structurally; an explicit note still belongs in the spec wording to make the intent obvious to readers.

## Patterns and Conventions to Follow

- **Mirror the surrounding agent's voice and verb choice.** The agent files are written in a direct, imperative voice ("Read X", "Verify Y", "Stop"). The summary instruction should match: "Overwrite `workflow.summary` with a fresh ~300–500 token prose summary covering ...". Do not introduce headings or formatting (like bullet lists *inside* the instruction) that diverge from the existing step style.

- **Place the summary write before the commit, not after.** Every agent's after-workflow section ends with: write step doc → stage files → commit → push. The summary write belongs between "write step doc" and "stage files" so the summary update lands in the same commit as the step doc — explicitly required by Acceptance Criterion in the spec.

- **Do not change commit messages.** The existing commit messages (`docs(spec): add spec for …`, `docs(research): add research for …`, etc.) are correct as-is. The summary update is folded into the existing commit; no message change is needed.

- **Match the existing `context.yaml` field comment style in the template.** Comments are short, inline, on the same line as the field, with longer prose for fields that need explanation broken into a follow-on comment block. The new `summary` field comment should mirror this — one line inline, plus an example block scalar in a comment underneath for shape guidance.

- **Place `summary` last in the `workflow` block, after `escalation_reason`.** The existing field order is `current_step`, `completed_steps`, `checkpoint`, `escalated`, `escalation_reason`. Appending `summary` keeps the additive-only nature of the change visible at a glance and avoids reordering noise in diffs. The in-flight `context.yaml` already follows this order (`escalation_reason` then `summary`).

- **Gate-read line should be a single bullet/item.** The new gate item should match the existing items' length and structure. Suggested wording (one line): "Read `workflow.summary` from `context.yaml` first — this is your primary handoff narrative. Read prior step docs (`1_spec.md`, etc.) only on demand when you need a specific detail the summary does not carry."

- **`agent-context/SKILL.md` section structure.** The new "Workflow summary" section should sit after "Resuming a disrupted workflow" and before "Artifacts registry", because it is workflow-state-level documentation, not registry-level. Use the same heading depth (`##`) as the surrounding sections.

- **Orchestrator wording for `/compact`.** Use the imperative voice the rest of `feature/SKILL.md` uses. Suggested step: "Invoke `/compact` to summarize the orchestrator's conversation history. Run this on every step transition. Do not run `/compact` when the post-return protocol halted at step 2 (`workflow.escalated: true`) — the conversation should stay intact for the user to inspect."

## Architectural Context

- **Subagents already run in isolated context windows.** Per the Claude Code documentation on the context window (`https://code.claude.com/docs/en/context-window`, fetched 2026-05-27), "The subagent works in its own separate context window. None of its file reads touch yours. Only the final summary comes back." This means each agent in `.claude/agents/` already has a fresh context — the orchestrator's `/compact` does **not** reduce the agents' loads. The agents' loads are reduced by the new "read `workflow.summary` first" gate instruction, which lets them defer (or skip) re-reading prior step docs. These are two halves of the same goal:
  - `/compact` reclaims orchestrator-side context (Approval Gate dialogue, post-return bookkeeping, anything the orchestrator reads itself).
  - `workflow.summary` reclaims downstream-agent-side context (prior step docs are no longer the default first read).

- **What `/compact` preserves.** Per the same doc: system prompt, output style, project-root `CLAUDE.md`, auto memory, and invoked skill bodies (capped at 5,000 tokens each, 25,000 total) all survive compaction. The conversation message history is replaced by a structured summary. This means the orchestrator can safely run `/compact` after every step transition without losing the project's CLAUDE.md, the `feature` skill body itself, or the `agent-context` skill body — those reload from disk and remain available.

- **`/compact` is a built-in slash command.** Confirmed at `https://code.claude.com/docs/en/commands` (fetched 2026-05-27): `/compact [instructions]` — "Free up context by summarizing the conversation so far. Optionally pass focus instructions for the summary." The spec calls for `/compact` to be invoked by name without arguments; that is the simplest form and matches the spec's intent.

- **Spec approval gate is informal.** The Research agent's gate hard-checks for the literal string `**Status:** Approved` in `1_spec.md` (`.claude/agents/research.md:24`), but the `/feature` orchestrator's Approval Gate (`.claude/skills/feature/SKILL.md:74-82`) does not update the spec file's `**Status:**` field when the user approves. This pre-existing inconsistency is **out of scope** for this feature, but worth surfacing because the in-flight feature's own `1_spec.md` still says `**Status:** Draft` even though Define has handed off — the orchestrator's hand-off, not the spec's text, is what advanced the workflow. The Planner should not be confused by this when validating the dry-run acceptance criterion.

- **The in-flight `context.yaml` is itself a worked example.** The Define agent has already written a ~300–500 token `workflow.summary` for this very feature (visible at `.docs/2026-05-27-context-compaction-handoff/context.yaml:19-67`), demonstrating the YAML block scalar shape, the three required content areas, and the prose voice. This is the cleanest reference example the Planner can point to. (This research step is about to overwrite that summary with a Research-step one, which itself becomes the next worked example.)

## Key Insights for the Planner

- **The change is mechanical and high-coverage.** Nine files, ~10 small inserts. No new files (excepting this research doc), no deletions, no renames, no semantics changes to existing fields. The Plan can be a single linear task list ordered by file; there are no dependencies between the edits beyond "template should be updated before agents start writing to the new field" (and even that is loose, since YAML tolerates missing fields).

- **Define is the asymmetry.** Every other agent gets two changes (gate read + after-workflow write). Define gets only one (after-workflow write) — there is no prior summary for it to read. The Plan task list should call this out explicitly so the Implementer doesn't accidentally add a gate-read step to Define.

- **Implement and Document have non-standard "after" structures.** Implement's after-workflow section is split across "After each task completes" (writes `checkpoint`) and "After all tasks complete" (commits and pushes). The summary write belongs in "After all tasks complete", *before* the existing `git status --porcelain` check, so the summary is part of whatever the final commit captures. Document's closing section is `## Commit and push documentation`, not `## After the workflow completes`; the summary write belongs in that section, before the commit.

- **The orchestrator's `/compact` placement matters.** The existing step 2 of the post-return protocol already short-circuits on `workflow.escalated: true`. So a naive "add `/compact` after push" already satisfies the "no compact on escalation" requirement, because the escalation halt happens before push is reached. The Planner should still add an explicit prose note in the protocol so the intent is documented, not just structurally enforced.

- **The `workflow.summary` field in the template should include an example.** The other free-text fields in the template (`checkpoint`, `escalation_reason`) are declared with one-line inline comments and no example. The summary is materially different — it has three required content areas and a prose voice that is hard to convey in a one-line comment. The template should include a brief example block scalar in a YAML comment block underneath the field declaration, so agents have a visible reference for what "good" looks like. The Define-written summary in the in-flight `context.yaml` is a good source for that example (trimmed for brevity).

- **No tests to write.** This repo has no test suite. Validation is the dry-run acceptance criterion below, plus a markdown-rendering eyeball check on the edited files. The Validate step should focus on (a) every agent's edits compile cleanly (no broken markdown headings, correct YAML in code fences), (b) the dry run succeeds, (c) the spec's Acceptance Criteria checkboxes can all be ticked.

- **Dry-run plan (how to exercise the acceptance criterion in this repo).** The spec calls for a dry run showing that after each step transition: (a) `workflow.summary` reflects the just-completed step in the committed `context.yaml` and covers the three required content areas, (b) `/compact` ran in the orchestrator's session, (c) the next agent's gate logs reading the summary. The natural way to exercise this is to use **this feature itself** as the dry run — once the changes land, the next time the workflow runs on a real feature, it produces evidence:
  1. After Define completes, `git show <commit> -- <feature>/context.yaml` shows the Define-written `workflow.summary` covering all three areas. ✓ Already true for this feature's Define run; the in-flight `context.yaml` is the evidence.
  2. The orchestrator's `/compact` invocation is observable in the session transcript — the post-return protocol announces "Pipeline halted" or "Starting [next]" wrapping a `/compact` call.
  3. The next agent's gate reads `workflow.summary`. Because gates run in the agent's own context window, the simplest observable evidence is the agent's opening message referencing the summary (e.g. "Per `workflow.summary`, Define produced …"). The Planner should add a one-sentence Plan task to instruct each agent to acknowledge having read the summary in its opening — making the read auditable without extra tooling. (Optional, but the spec's "next agent logs reading the summary" criterion implies this kind of self-report.)
  4. Validate the chain by running `/feature` against a small throwaway feature (e.g. "rename a constant in CLAUDE.md") and walking through all six steps. The whole loop should complete inside a single session with each handoff producing a committed summary and a `/compact` call.

- **There is a small chicken-and-egg risk.** This research step is producing the second `workflow.summary` for this very feature *before* the agent files have been updated to require it. The current Research agent file does not yet contain the "write `workflow.summary` before returning" instruction — yet the user's invocation message explicitly asks for it. The Planner can treat this research step as setting precedent for what the Implementer needs to bake into the agent definitions; nothing here is blocked by it. The first "real" enforcement begins after Implement lands.

## Artifacts

None. All findings live in this document. The in-flight `context.yaml` and `1_spec.md` are sufficient worked examples — copying them into `artifacts/` would duplicate state already tracked in the feature folder.

## Open Questions

- **Should the spec's `**Status:**` field flip to `Approved` when the orchestrator's Approval Gate passes?** Not introduced by this feature, pre-existing inconsistency. The Plan should *not* take this on — it's a separate fix. Flagged for visibility only.

- **Should `/compact` pass focus instructions?** The spec calls for a bare `/compact` invocation. The built-in command accepts optional focus instructions (e.g. `/compact "preserve the post-return protocol state machine"`). Bare invocation is simpler and matches the spec; no question to resolve here unless the Planner explicitly wants to revisit. Listed for awareness.

- **Should each agent's "I read the summary" acknowledgment be required by the spec, or just suggested?** The spec's acceptance criterion says "the next agent's gate logs reading the summary as its primary handoff context" but does not specify the form of the log. Suggested resolution: the Plan should add a Plan task to each agent's gate edit that instructs the agent to acknowledge in its opening message (e.g. one sentence: "Per the summary in `workflow.summary`, the prior step accomplished …"). Surfaced for the Planner to decide.
