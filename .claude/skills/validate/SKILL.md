---
name: validate
description: Use after implementation to run a change through senior code review, a conditional frontend design review, and QA review before it ships — fixing findings and re-reviewing until they pass. The Validate step of the feature workflow.
disable-model-invocation: true
allowed-tools: Read Bash(*) Agent
---

# Validate

The last gate before a change ships. Run a senior code review, a conditional design review (only when the change touches frontend), then a QA review; fix findings between rounds and repeat until each passes. Do not soften findings, rush approvals, or skip steps because the implementation looks mostly fine.

Run this **from the main session** — it spawns the `senior-review`, `design-review`, and `qa-review` agents, and subagents can't spawn subagents. Spawning them in isolated contexts is the point: an independent reviewer that didn't write the code won't rubber-stamp it.

`autorun` calls this skill as its always-run end-of-run review pass, and reuses its loop shape (bounded fix iterations) for per-task reviews of risky tasks.

## Pre-flight — mechanical checks first

Before spawning any review agent, run [`project-checks`](../project-checks/SKILL.md) once over the change — typecheck, lint, format, spell, tests, discovered from the project. Fix (or auto-fix) anything red **before** Round 1. A failing mechanical check means a review round would be wasted on noise that the pipeline would reject anyway, so fail fast and cheap here. Only proceed to the senior review once the tree is green.

## When NOT to use

Trivial changes (typo, copy, config) don't need the full gate — a quick `senior-review` in-session is enough. Reserve `validate` for real features and risky changes.

## Round 1 — Senior code review

1. Spawn the **`senior-review` agent** (Agent tool). Pass the spec and plan if they exist, plus the diff scope.
2. If it returns findings: fix each exactly as specified, run the test suite to confirm nothing broke, commit the fixes (`Skill(git-commit)` first), and re-spawn the agent.
3. Repeat until it approves — **max 3 fix iterations**. If the same issues persist after 3, stop and report which remain, what was tried, and your assessment of the root cause. Do not attempt a 4th.

Do not advance to the design review until the senior review approves.

## Round 2 — Design review (conditional)

Runs **only when the change touches frontend** — component, markup, or style files (`.tsx/.jsx/.vue/.svelte`, CSS/SCSS/Tailwind, HTML/templates). On a non-frontend change, the agent no-ops gracefully ("No frontend changes — nothing to review") and validate skips straight to Round 3; this round never blocks a backend-only or docs-only change.

1. Spawn the **`design-review` agent** (Agent tool) in **runtime mode** — validate reviews your own pre-ship code, so running the app via the Chrome DevTools MCP is fine. (The agent falls back to static review gracefully when the app can't run or the Chrome MCP isn't configured.) Pass the spec and plan if they exist, plus the diff scope.
2. If it returns findings: fix each exactly as specified, re-run [`project-checks`](../project-checks/SKILL.md) to confirm nothing broke, commit the fixes (`Skill(git-commit)` first), and re-spawn the agent.
3. Repeat until it approves — **max 3 fix iterations**, same stop rule as Round 1: if the same issues persist after 3, stop and report which remain, what was tried, and your assessment of the root cause. Do not attempt a 4th.

Do not advance to QA until the design review approves (or is skipped as a non-frontend change).

## Round 3 — QA review

1. Spawn the **`qa-review` agent**. It runs the e2e suite first (graceful when none exists), then audits coverage and test quality.
2. If it returns **Gaps**: fix each, run the suite, verify coverage holds, commit, and re-spawn — **max 3 iterations**, same stop rule as Round 1.
3. If it returns **Blocked** (e2e couldn't reach green in 3 attempts, or a required runtime is missing): stop and report; don't force an approval.
4. **Green-suite gate:** if QA reports Approved but the final state wasn't "e2e green (or absent-and-noted)," treat it as a defect and re-spawn with the gap called out (counts against the Round 3 cap).

## Completion

Produce a validation summary: senior verdict + fix-iteration count; design verdict + fix-iteration count (or "skipped — no frontend changes"); QA verdict, coverage, fix-iteration count, and the e2e result; each finding that required a fix and what resolved it; any evidence captured.

Record per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md): standalone, present the summary in-session; beads-enhanced, record it on the feature epic and close out resolved finding issues.

Then push the branch (`git push`) to flush any fix commits made during the rounds. Hand off to the `document` skill for the final documentation pass and PR (see `feature-workflow`).
