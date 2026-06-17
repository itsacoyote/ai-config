---
name: project-checks
description: Use after implementing a task, or as a pre-flight before the Validate review gate, to run the project's own mechanical quality gates — typecheck, lint, format, spellcheck, tests.
allowed-tools: Read Glob Grep Bash(test *) Bash(command -v *) Bash(ls *)
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

## Step 1 — Discover what the project actually defines

Detect the toolchain; **only run what exists.** Check in this order and stop at the first
layer that covers a category:

1. **JS/TS — `package.json` scripts.** Read it and look for scripts named (or prefixed)
   `lint`, `typecheck` / `type-check` / `tsc`, `format` / `format:check` / `fmt`,
   `spell` / `cspell`, `test`. Use the project's package manager — infer from the lockfile:
   `pnpm-lock.yaml`→`pnpm`, `yarn.lock`→`yarn`, `bun.lockb`→`bun`, else `npm run`.
2. **`Makefile` / `Justfile` targets** — `make lint`, `make fmt`, `make check`, `make test`
   (or `just …`).
3. **`.pre-commit-config.yaml`** — `pre-commit run --all-files` (or `--files <changed>`)
   bundles many of these.
4. **Language-native, when no script wraps them:**
   - **Rust:** `cargo fmt --check`, `cargo clippy`, `cargo test`
   - **Go:** `gofmt -l .`, `go vet ./...`, `golangci-lint run`, `go test ./...`
   - **Python:** `ruff check`, `ruff format --check` (or `black --check`), `mypy`, `pytest`

```bash
# example probes — adapt to what you find
test -f package.json && echo "node project"
command -v pnpm >/dev/null && ls pnpm-lock.yaml 2>/dev/null
```

Report the set you found (e.g. "found: lint, typecheck, test — no format/spell script") before
running, so it's clear what's covered and what isn't.

## Step 2 — Run, fast checks first

Run cheapest-to-slowest and **fail fast**: format → lint → typecheck → spellcheck → tests.
A formatting or type break is found in seconds; don't pay for the test suite to learn the code
doesn't compile.

Prefer scoping to the **touched files** when the tool supports it (`eslint <files>`,
`prettier --check <files>`, `cspell <files>`); fall back to whole-project when it doesn't.

Skip a check whose inputs haven't changed since it last passed — re-running an unchanged check
adds no information (same discipline as `incremental-implementation`'s checklist note).

## Step 3 — On failure: auto-fix, then block

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
