---
name: validate
description: Use after implementation to run a change through senior code review, a security scan, a conditional frontend design review, and QA review before it ships — fixing findings and re-reviewing until they pass. The Validate step of the feature workflow.
disable-model-invocation: true
allowed-tools: Read Bash(*) Agent
---

# Validate

The last gate before a change ships. Run a senior code review, a security scan, a conditional design review (only when the change touches frontend), then a QA review; fix findings between rounds and repeat until each passes. Do not soften findings, rush approvals, or skip steps because the implementation looks mostly fine.

Run this **from the main session** — it spawns the `senior-review`, `security-scan`, `design-review`, and `qa-review` agents, and subagents can't spawn subagents. Spawning them in isolated contexts is the point: an independent reviewer that didn't write the code won't rubber-stamp it.

`autorun` runs this review pass at the end of its loop — **reading and following this skill directly** (it can't invoke a `disable-model-invocation` skill via the Skill tool), and reusing its loop shape (bounded fix iterations) for per-task reviews of risky tasks.

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`test -d .beads && command -v bd >/dev/null 2>&1`. If it is NOT, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

## Pre-flight — mechanical checks first

Before spawning any review agent, run [`project-checks`](../project-checks/SKILL.md) once over the change — typecheck, lint, format, spell, tests, discovered from the project. Fix (or auto-fix) anything red **before** Round 1. A failing mechanical check means a review round would be wasted on noise that the pipeline would reject anyway, so fail fast and cheap here. Only proceed to the senior review once the tree is green.

## When NOT to use

Trivial changes (typo, copy, config) don't need the full gate — a quick `senior-review` in-session is enough. Reserve `validate` for real features and risky changes.

## Computing the diff scope

Before each spawn, compute the **branch diff scope** (per [`.claude/references/diff-scope.md`](../../references/diff-scope.md)) and include it in the agent dispatch:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
base=$(git merge-base HEAD ${BASE:-main})
head=$(git rev-parse HEAD)
files=$(git diff --name-only $base $head)
# Dispatch line: "Diff scope: $base..$head — changed files: $files"
```

**Recompute at each spawn.** Fix commits move HEAD between rounds — a scope pinned at Round 1 would miss those commits. Recompute `head` and `files` immediately before each `Agent(...)` call so the reviewer sees current HEAD.

## Round 1 — Senior code review

1. Compute the diff scope (above), then spawn the **`senior-review` agent** (Agent tool). Pass the spec and plan if they exist, plus the computed diff scope.
2. If it returns findings: fix each exactly as specified, run the test suite to confirm nothing broke, commit the fixes (`Skill(git-commit)` first), and re-spawn the agent.
3. Repeat until it approves — **max 3 fix iterations**. If the same issues persist after 3, stop and report which remain, what was tried, and your assessment of the root cause. Do not attempt a 4th.

Do not advance to the security review until the senior review approves.

## Round 2 — Security review

1. Recompute the diff scope, then spawn the **`security-scan` agent** (Agent tool). Pass the diff scope (spec and plan if present). **This round is non-optional and must run as an independent agent.** If the `security-scan` agent can't be dispatched — e.g. it isn't installed in `.claude/agents/` — **stop and report a setup defect**; do **not** fall back to reviewing security inline. An in-context security pass defeats the fresh-context independence the round exists for (it's the same context that may have written the code), and a missing agent is fixed by installing it, not worked around.
2. If it returns CRITICAL or HIGH findings: fix each exactly as specified, run the test suite to confirm nothing broke, commit the fixes (`Skill(git-commit)` first), and re-spawn the agent.
3. Repeat until no CRITICAL or HIGH findings remain — **max 3 fix iterations**. If CRITICAL or HIGH findings persist after 3, stop and report which remain, what was tried, and your assessment of the root cause. Do not attempt a 4th. MEDIUM/LOW/INFO findings are surfaced in the summary but do not block advancement.

Do not advance to the design review until the security review reports no CRITICAL or HIGH findings.

## Round 3 — Design review (conditional)

Runs **only when the change touches frontend** — component, markup, or style files (`.tsx/.jsx/.vue/.svelte`, CSS/SCSS/Tailwind, HTML/templates). On a non-frontend change, the agent no-ops gracefully ("No frontend changes — nothing to review") and validate skips straight to Round 4; this round never blocks a backend-only or docs-only change.

1. Recompute the diff scope, then spawn the **`design-review` agent** (Agent tool) in **runtime mode** — validate reviews your own pre-ship code, so running the app via a browser MCP (the Chrome DevTools MCP, or Playwright as a fallback) is fine. (The agent falls back to static review gracefully when the app can't run or no browser MCP is configured.) Pass the spec and plan if they exist, plus the computed diff scope.
2. If it returns findings: fix each exactly as specified, re-run [`project-checks`](../project-checks/SKILL.md) to confirm nothing broke, commit the fixes (`Skill(git-commit)` first), and re-spawn the agent.
3. Repeat until it approves — **max 3 fix iterations**, same stop rule as Round 1: if the same issues persist after 3, stop and report which remain, what was tried, and your assessment of the root cause. Do not attempt a 4th.

Do not advance to QA until the design review approves (or is skipped as a non-frontend change).

## Round 4 — QA review

1. Recompute the diff scope, then spawn the **`qa-review` agent**. Pass the diff scope. It runs the e2e suite first (graceful when none exists), then audits coverage and test quality.
2. If it returns **Gaps**: fix each, run the suite, verify coverage holds, commit, and re-spawn — **max 3 iterations**, same stop rule as Round 1.
3. If it returns **Blocked** (e2e couldn't reach green in 3 attempts, or a required runtime is missing): stop and report; don't force an approval.
4. **Green-suite gate:** if QA reports Approved but the final state wasn't "e2e green (or absent-and-noted)," treat it as a defect and re-spawn with the gap called out (counts against the Round 4 cap).

## Security backstop — a `security-sensitive` task must not ship unscanned

Round 2 runs unconditionally, so a normal branch diff is already covered. This backstop catches the failure mode where the security round was **skipped or silently inlined** — a missing agent, an interrupted run — while the work included tasks the planner flagged for security. That is exactly how a scan gets lost without anyone noticing.

Before producing the summary, query beads for epic children carrying the `security-sensitive` marker the planning step records (see [`planning-and-task-breakdown`](../planning-and-task-breakdown/SKILL.md)):

```bash
bd list --json | jq -r '.[] | select((.labels // []) | index("security-sensitive")) | .id'
# If the planner recorded it as a body marker (`Security-sensitive: yes`) instead of a label, match that line in the issue body.
```

If that returns nothing, there is nothing extra to assert — proceed. If it returns any task, **completion is blocked until** the validation summary records that Round 2's independent `security-scan` agent actually ran to a no-CRITICAL/HIGH verdict over a diff scope that includes those tasks' files. If Round 2 didn't run, was inlined, or its scope didn't cover them, go back and run it now — do **not** push or hand off to `document`. A `security-sensitive` task shipping without an independent scan is a gate failure, not a warning.

## Completion

Produce a validation summary: senior verdict + fix-iteration count; security verdict (highest severity found, fix-iteration count, and any unresolved MEDIUM/LOW/INFO items) — plus, if the backstop found any `security-sensitive` task, explicit confirmation the independent scan covered it; design verdict + fix-iteration count (or "skipped — no frontend changes"); QA verdict, coverage, fix-iteration count, and the e2e result; each finding that required a fix and what resolved it; any evidence captured.

Record the validation summary on the feature epic and close out resolved finding issues — beads is the system of record. See [`.claude/references/beads.md`](../../references/beads.md) for the full model.

Then push the branch (`git push`) to flush any fix commits made during the rounds. Hand off to the `document` skill for the final documentation pass and PR (see `feature-workflow`).
