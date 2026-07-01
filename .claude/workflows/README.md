# Workflows

[Dynamic workflows](https://code.claude.com/docs/en/workflows) are JavaScript scripts the
Claude Code runtime executes in the background, orchestrating many subagents from a script
Claude wrote and you can rerun. A saved script here becomes a `/<name>` command.

**Prerequisite:** Claude Code v2.1.154+ with dynamic workflows enabled (paid plan; toggle in
`/config` on Pro). If workflows are off, the equivalent **skills still work** — every workflow
here is an *optional accelerator* for a step the skill library already implements, never a
replacement. The repo does not depend on workflows being enabled.

## When a workflow (vs. a skill/agent)

Reach for a workflow when a step is **already non-interactive and fan-out-heavy** — many agents,
no mid-run human decisions, and results worth cross-checking. A workflow moves the plan into
code: the loop, branching, and intermediate results live in the script, so the session's context
holds only the final report.

**Not** a fit for the supervised conductor (`autorun`) or the conversational `define` step:
workflows take **no mid-run human input** (only agent permission prompts can pause a run), and
their agents run in `acceptEdits` with file edits auto-approved. Steps that need human triage,
sign-off, or a plan-revision loop stay as skills/agents.

## Available workflows

| Command | What it does |
|---|---|
| `/validate-fanout` | Fans out the Validate step — parallel `senior-review` / `security-scan` / `qa-review` (+ `design-review` if the diff is frontend), adversarially verifies each finding, and returns a ranked report. **Review-only:** applying fixes and committing stays with the caller (you or `autorun`). Optional `args`: `{ range: "<base>..<head>", epic: "<beads-epic-id>" }`. |

## Design notes that apply to all workflows here

- **The script has no filesystem/shell access** — only the agents it spawns do. Anything that
  touches git, `bd`, or the tree happens inside an `agent(...)` call.
- **Fixing/committing belongs to the caller**, not the workflow. Parallel agents editing one
  branch would race, and there is no human to sign off mid-run. Workflows here review, verify,
  and report; the main session or `autorun` applies fixes and owns the beads lifecycle + push.
- **Portability:** these travel in `.claude/` like the skills. They reference repo files by
  relative path (e.g. `.claude/references/diff-scope.sh`), so they work after a copy-paste as
  long as those files come along.
