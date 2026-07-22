---
name: autorun
description: Use when an approved Define spec should proceed through Research → Plan → Implement → Validate → Document under supervision, with fresh serialized workers and only the Define and PR human gates.
metadata:
  category: workflow
---

# Autorun

Supervised execution of **Define → Research → Plan → Implement → Validate → Document**. Autorun begins only after an approved Define spec (**human gate 1**) and stops after Document has prepared the pull request handoff (**human gate 2**). It reasons between gates, but consequential actions remain subject to the parent harness's approvals and exception stops.

## When NOT to use

- Trivial work where the full workflow adds ceremony without safety.
- Any run that cannot be actively supervised. This is not a headless, overnight, or permission-bypassing loop.
- Work without an approved spec and feature epic; return to `define` instead.

**Preflight (required).** Before doing any workflow work, resolve
`../../scripts/beads-preflight.sh` relative to this skill's directory and execute the resolved
absolute path. If it exits non-zero, **stop** and tell the user to run `setup-beads`, then retry.

## Preconditions

Require an **approved Define spec** in a named beads epic. Compute the approval revision from only the JSON `description` string returned by `bd show <epic> --json`: decode as UTF-8, normalize CRLF/CR to LF, remove trailing LF characters, append exactly one LF, then calculate SHA-256 and format lowercase `sha256:<64 hex>`. Comments, status, labels, and approval metadata are excluded. Gate 1 is valid only when the epic has an approval record naming that exact digest. If explicit approval exists in the current human conversation but no record exists yet, the parent records `Define approval: <digest>` before proceeding. Recording and verification use this same algorithm. A missing marker, changed description, or digest mismatch returns to human gate 1; never infer approval from the epic's existence.

Read [`feature-workflow`](../feature-workflow/SKILL.md), [`isolated-worker-orchestration.md`](../../references/isolated-worker-orchestration.md), and the neutral role manifest. Resolve `../../scripts/validate-roles.py` from this loaded skill directory, execute its absolute path, and stop on an invalid role contract.

Run in the parent session that owns human interaction, synthesis, beads mutations, retry counters, and permissions. Never weaken sandboxing or approval policy. Workers never ask the human or spawn nested workers.

## Harness routing

- **Codex:** dispatch the matching custom role from `.codex/agents/`. Read-only roles retain read-only sandboxing; the single implementer inherits the supervised parent policy.
- **Pi:** resolve `scripts/run-pi-implementer.sh` from this skill bundle and invoke its absolute path for implementation; never call the generic runner directly for a writer. The wrapper fails closed unless a trusted external sandbox launcher is configured outside the worktree. It passes only task-approved writable paths, mounts trusted orchestration read-only, clears remote/GitHub credentials, and disables outbound network before constructing and invoking the isolated Pi process. Parent-approved dependency fetching happens outside the worker. Read-only Pi roles still use the absolute `../../scripts/run-pi-role.sh` path.
- **Other clients:** use isolated workers only when complete neutral prompts/skills and role modes are preserved. Otherwise exception-stop.

Provider names, model aliases, and client-specific dispatch syntax do not belong in task records or neutral prompts.

## Ordered run

1. **Research** — follow [`research`](../research/SKILL.md). Persist the synthesis to the epic. Under Pi, prefer its dedicated Research session; under Codex, independent read-only lenses may fan out. Skip ask-first history research unless it was approved before the supervised run.
2. **Plan** — follow [`planning-and-task-breakdown`](../planning-and-task-breakdown/SKILL.md). Record dependency-ordered leaf tasks, file-map slices, acceptance criteria, named tests, skill hints, and routing labels.
3. **Plan review** — dispatch `plan-review` with the approved spec and complete plan. The role is read-only. The parent may revise beads tasks and rerun it, **bounded to 3** review attempts. A fundamentally wrong approach or unresolved substantive finding exception-stops back to the human.
4. **Implement** — drain tasks using the serialized loop below.
5. **Validate** — follow [`validate`](../validate/SKILL.md) completely, including independent security and schema-gated QA behavior.
6. **Document** — follow [`document`](../document/SKILL.md). Prepare documentation and the draft-PR handoff, then stop for human gate 2. Do not silently push, create, ready, approve, or merge a PR.

Advance only when the previous step has a valid recorded result.

## Serialized implementation loop

The parent owns issue lifecycle. The `implementer` reads named beads records but never claims or closes them.

### Durable writer lease and resume before ready work

Before each implementation launch in **every harness**, resolve `scripts/writer-lease.py` from this skill and use it to acquire the one canonical atomic lease at the worktree Git path `autorun-writer.lock`. The helper records owner ID/PID, task ID, worker PID when attached, and pre-task SHA. Persist the same values on the task before spawning. Every Codex, Pi, or other implementation dispatch fails closed unless this shared lease is held.

Hold the lease through worker result validation, changed-path inspection, every review/fix iteration, and verified `bd close`. Release it only at terminal close, or at an exception-stop after confirming no worker process remains alive. Never release between implementation and review.

`bd ready` excludes claimed work. On every invocation:

1. List leaf tasks under the epic with status `in_progress`.
2. Read each task's persisted pre-task SHA and lease/worker identity. If a prior worker may still be alive, do not overlap it: wait or exception-stop. Clear a lease only after verifying its owner terminated, never merely because it is old.
3. Reacquire the per-worktree lease and re-dispatch the stranded task without claiming it again.
4. Run that resumed task through the **same** status handling, changed-path inspection, pinned pre-task-SHA review cadence, and verified `bd close` sequence below.
5. Only after no stranded task remains, drain implementable leaf tasks from `bd ready`; skip epics and containers.

For each ready or safely reclaimed task:

1. For new work, select the highest-priority dependency-unblocked leaf; for resumed work, use the safely reclaimed stranded task.
2. For new work, run `bd update <id> --claim` and verify its status became `in_progress`; do not reclaim a resumed task.
3. For newly claimed work, record current HEAD as the durable pre-task SHA. For resumed work, preserve the existing persisted pre-task SHA unchanged. Record the task file-map allowlist and acquired writer lease identity in both cases.
4. Dispatch **exactly one `implementer`** with the task description, acceptance criteria, named tests, file-map slice, skill hints, routing labels, epic/task/dependency IDs, and permission to pull only named context with `bd show`.
5. Wait for its status and inspect changed paths, checks, and commit evidence.
6. Run the required per-task review cadence.
7. Only on accepted implementation and review, run `bd close <id>` and verify status `closed`.

**Never dispatch a second source-writing worker** while one is running. Verification and read-only review may not overlap a writer in the same worktree. Any review fix is another bounded request to exactly one implementer after the previous worker exits.

Statuses follow [`subagent-status-protocol.md`](../../references/subagent-status-protocol.md):

- `DONE` — inspect scope/check evidence, review, then close.
- `DONE_WITH_CONCERNS` — resolve correctness concerns before close; record observational follow-up work.
- `NEEDS_CONTEXT` — supply only the missing context and redispatch the same task, bounded to 3 attempts total.
- `BLOCKED` — exception-stop; do not blind-retry or advance.

A failed worker process or any missing, malformed, duplicated, or unknown status is treated exactly as `BLOCKED`: retain the task as `in_progress`, exception-stop, and never close or advance it.

A worker status does not mutate beads by implication. The parent verifies each explicit claim/close transition.

## Per-task reviews

For every non-trivial task, dispatch `efficiency-review`. Also dispatch:

- `senior-review` for `risk:review-per-task` tasks or parent-identified high blast radius;
- `security-scan` for every `security-sensitive` task, independently of senior review;
- `design-review` for frontend-risk tasks.

Use the task's commit-before-work through current-HEAD range as pinned scope and recompute it after every fix. Reviewers return findings only. Route fixes through one serialized implementer and rerun the applicable reviewer, bounded to 3 fix iterations. End-of-run Validate always runs regardless of per-task cadence.

## Exception stops

Stop and return control to the human when:

- plan review says the premise must return to Define;
- a review remains blocking after 3 iterations;
- a worker returns `BLOCKED` or exhausts context retries;
- a permission is denied and no approved safe path remains;
- beads status, git scope, or worker write boundaries cannot be verified.

Report the task, attempted actions, evidence, and likely cause. An exception stop is a safety halt, not an extra routine gate.

## Terminal state

Success means all planned leaf tasks are closed, Validate approved, and Document prepared the final docs and draft-PR material. The branch then waits at **human gate 2**. Autorun never marks a PR ready, approves it, requests changes, merges it, or bypasses signing/push policy.

Because beads is the system of record, a later invocation resumes from verified `in_progress`, `open`, and `closed` states rather than reconstructing progress from conversation memory. See [`beads.md`](../../references/beads.md).
