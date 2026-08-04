---
name: project-checks
description: Use after implementing a task, or as a pre-flight before the Validate review gate, to run the project's own mechanical quality gates — typecheck, lint, format, spellcheck, tests.
allowed-tools: Read Glob Grep Bash(test *) Bash(command -v *) Bash(ls *) Bash(sh ${CLAUDE_SKILL_DIR}/scripts/project-checks.sh*) Bash(bash ${CLAUDE_SKILL_DIR}/scripts/project-checks.sh*)
---

# Project Checks

Run the project's **mechanical** quality gates — the deterministic, runnable checks
(typecheck, lint, format, spellcheck, tests) every project ships in `package.json` scripts,
a `Makefile`, or its language toolchain. Run them **after each implementation task** and as a
**fast pre-flight before the Validate gate**, so breakage and cruft don't quietly accumulate
to the end of a feature.

These are not the same as the judgment review in [`validate`](../validate/SKILL.md)
(`senior-review` + `qa-review`). Those are slow, expensive, end-of-feature, and need a human
or an agent to reason. **Project-checks are cheap, mechanical, and run constantly** — they're
the fast green-tree gate that keeps every task landing clean so the expensive review isn't
wasted on lint noise.

## When to use

- **Before every commit** — the primary trigger. Run the checks as the last step before
  `git commit` (see [`git-commit`](../git-commit/SKILL.md)) so you never commit something
  that breaks CI on GitHub. This is the local mirror of the CI gate: catch it here, not in a
  red pipeline.
- **After each task** during `incremental-implementation` (and inside the `implementer`
  agent before it reports a task DONE) — the per-task green gate. In the standard
  implement→test→verify→commit cycle, this *is* the verify step.
- **As a pre-flight in `validate`** — run once before spawning the review agents, so an
  obvious lint/type break fails fast and cheap instead of after a full review round.

## When NOT to use

- The project defines **no** matching checks — skip gracefully, don't invent commands or
  install tooling. Report "no project checks found" and move on.
- As a substitute for `senior-review` / `qa-review` — green checks don't mean correct or
  well-tested. This gate is necessary, not sufficient.

## Step 1 — Discover and run the checks

Run the script from the repo root. It does the deterministic part: detect the toolchain the
project actually defines, then run the checks cheapest-first (format → lint → typecheck →
spell → test), failing fast.

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/project-checks.sh          # discover + run, fail-fast
sh ${CLAUDE_SKILL_DIR}/scripts/project-checks.sh --list   # discover only — print the plan, run nothing
sh ${CLAUDE_SKILL_DIR}/scripts/project-checks.sh -k       # --keep-going: run all even after a failure
```

What the script does for you, so you don't re-derive it each time:

- **Detects the package manager** from the lockfile (`pnpm-lock.yaml`→`pnpm`, `yarn.lock`→`yarn`,
  `bun.lockb`→`bun`, else `npm run`).
- **Only runs what exists**, picking one command per category by precedence: `package.json`
  script → `Makefile` target → `Justfile` target → language-native (Rust / Go / Python). It
  prefers non-mutating script variants (`format:check` over `format`) and ignores `*:fix`.
- **Prints the discovered plan first**, then runs in order. If the project defines nothing, it
  reports "no project checks found" and exits 0 — that's the graceful skip; don't invent
  commands or install tooling.

The script is **non-mutating** — it runs checks in check mode and reports failures; it does
**not** auto-fix. That decision (Step 2) is yours. Its exit code is 0 (all passed / nothing to
run) or 1 (a check failed).

**Two things the script does not do — apply them yourself when they help:**

- **Scope to touched files** when the tool supports it (`eslint <files>`, `prettier --check
  <files>`, `cspell <files>`) for a faster pre-commit gate. The script runs the project's own
  whole-project command; for a tight inner loop you can run a scoped command by hand instead.
- **Skip a check whose inputs haven't changed** since it last passed — re-running it adds no
  information (same discipline as `incremental-implementation`'s checklist note).

If a flag or detection looks wrong for this project (the CLI/toolchain evolved), update the
script — that's the single place the discovery logic lives.

## Step 2 — On failure: auto-fix, then block

1. **Auto-fixable categories — fix first, then re-run the check:**
   - format: `prettier -w`, `ruff format`, `cargo fmt`, `gofmt -w`
   - lint: `eslint --fix`, `ruff check --fix` (only the safe, auto-fixable rules)
2. **Non-auto-fixable** (typecheck, spellcheck, failing tests) — fix the underlying code, or
   surface it. Don't suppress with ignores/`any`/`// eslint-disable` to force green.
3. **If a check still fails after auto-fix, the task is not done.**
   - In the **main session** (manual implement): fix it before moving to the next task.
   - In the **`implementer` agent**: return **DONE_WITH_CONCERNS** or **BLOCKED**
     (per [`subagent-status-protocol`](../../references/subagent-status-protocol.md)) with the
     failing command and its output — don't report a clean DONE over a red check.
   - In **`validate`'s pre-flight**: stop before spawning the review agents and fix; a red
     pre-flight means the review round would be wasted.

Keep the tree green at every task boundary. That's the whole point: small, constant cleanup
beats one big untangling at the end.
