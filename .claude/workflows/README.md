# Workflows

[Dynamic workflows](https://code.claude.com/docs/en/workflows) are JavaScript scripts the
Claude Code runtime executes in the background, orchestrating many subagents from a script
Claude wrote and you can rerun. A saved script here becomes a `/<name>` command.

**Prerequisite:** Claude Code v2.1.154+ with dynamic workflows enabled (paid plan; toggle in
`/config` on Pro). If workflows are off, the equivalent **skills still work** — every workflow
here is an *optional accelerator* for a step the skill library already implements, never a
replacement. The repo does not depend on workflows being enabled.

## Cost and scale — read before a big run

A workflow spawns many agents, so it costs **meaningfully more tokens** than doing the same
work in one conversation. In a smoke test, `/validate-fanout` spent **~482k tokens reviewing a
2-file diff** — almost entirely startup overhead (each agent loads its methodology and orients
in the repo before doing any real work).

**Does it get more efficient with larger jobs?** Per unit of work, somewhat — the fixed
per-agent overhead amortizes across more real work. But the **total** cost still rises with
size (more files to read, more findings to verify). A big job isn't cheaper; its tokens are
just spent on *work* instead of *overhead*.

**So why spend it?** Because the alternative — one conversation — either can't hold the job
(its context overflows and degrades) or can't parallelize it. You spend workflow tokens to buy
capabilities a single context can't give you:

- **Work too big for one context** — a 500-file migration, a whole-codebase audit.
- **Wall-clock speed** — up to 16 agents at once instead of one slogging serially.
- **Independent, adversarial judgment** — fresh contexts that didn't write the code catch what
  one anchored context rubber-stamps.
- **Repeatability** — codified orchestration you rerun identically.

**Rule of thumb:** reach for a workflow when the job is **too big to hold in one head**, or when
**being right is worth more than the tokens** (migration, security audit, cross-checked
research). For everyday, small-to-medium review — a typical PR diff — the plain `validate`
skill is the right tool and a fraction of the cost. Gauge spend by running on a small slice
first, and watch per-agent token usage live in `/workflows`.

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
- **Caller still owns completion.** `/validate-fanout` reviews and reports only. The `validate`
  skill's security-sensitive backstop (query beads for `security-sensitive` tasks and block
  completion until an independent scan covers them), the beads close-out, and the push all
  remain the caller's responsibility — the workflow does not perform them.
