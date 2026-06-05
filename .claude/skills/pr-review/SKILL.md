---
name: pr-review
description: Use when reviewing someone else's GitHub pull request by number and posting the review back — a comment-only, multi-lens review that never approves, rejects, requests changes, merges, or edits anything. Distinct from validate (which reviews your own pre-ship code). Run from the main session.
disable-model-invocation: true
argument-hint: "<pr-number>"
allowed-tools: Read Bash(gh pr view *) Bash(gh pr diff *) Bash(gh issue view *) Bash(gh api -X GET *) Bash(gh repo view *) Bash(git status*) Bash(git branch *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(bd *) Agent
---

# PR Review

A developer-invoked, comment-only review of a GitHub pull request. Point it at a PR number and
it gathers the PR's full context, checks the branch out locally, runs four read-only review
passes in isolated subagents, compiles their findings into one prioritized list, walks that
list with you, and posts the kept items as a **single `event=COMMENT` review** — inline where
they concern code, in the body where they don't.

It is **structurally incapable of approving, rejecting, requesting changes, merging, closing,
or editing** the PR, the repo, or any code. Its only outward action is posting comments. See
the [Guardrails](#guardrails) section — it is the centerpiece of this skill, not an afterthought.

**This is not `validate`.** [`validate`](../validate/SKILL.md) reviews **your own** pre-ship
code and fixes findings in a loop before shipping. `pr-review` reviews **someone else's** PR and
**never fixes anything** — it compiles, gates with you, and posts comments. Different target,
different posture: one patches, this one only comments.

## When NOT to use

- Reviewing your own pre-ship change — use [`validate`](../validate/SKILL.md).
- You want to approve, request changes, or merge a PR — this skill will never do that; do it
  yourself with `gh`.
- A trivial PR (typo, one-line config) — a direct read and a manual `gh pr comment` is enough;
  the four-pass machinery isn't worth it.

## Before you run

- **Run from the main session.** It spawns the review subagents and runs the human curation
  gate — a subagent can do neither.
- **Keep permissions on.** `allowed-tools` is read-only by design (see Guardrails). The two
  consequential actions — the `gh pr checkout` and the final post — are **not** in the
  allowlist, so they surface permission prompts you approve. This is what keeps you in the loop
  and lets the workflow run where `--dangerously-skip-permissions` is forbidden. **Never** route
  around this.
- GitHub access is via the `gh` CLI per the
  [`github-tool-preference`](../../rules/github-tool-preference.md) rule; raw `gh api` is used
  only where a subcommand doesn't exist (posting the review; inline review-thread comments),
  and reads pin the method (`gh api -X GET …`).

## The run

Detect beads mode first per [`.claude/references/beads.md`](../../references/beads.md) — it
governs the Record step and how status is tracked.

### 1. Intake

Gather the PR's surrounding context, then check the branch out. Commands are verified against
`gh` 2.93.

```bash
# PR metadata, files, comments, reviews, and linked-issue linkage in one call
gh pr view <n> --json number,title,body,headRefName,headRefOid,baseRefName,files,comments,reviews,closingIssuesReferences

# conversation + review-thread comments (read-only gh subcommand)
gh pr view <n> --comments

# the diff reviewers anchor against
gh pr diff <n>
```

- **Linked issue:** prefer `closingIssuesReferences[]` (GitHub's real "closes" linkage) over
  regex-parsing the body. For each referenced issue: `gh issue view <num> --json
  title,body,state,labels,comments`. If there is none, **note the absence and proceed** — do
  not fail.
- **Commit pin:** capture `headRefOid` (use as `commit_id` when posting, pinning comments to
  the reviewed commit) and `headRefName` (the checkout target).
- **Checkout — only from a clean tree, and restore afterward:**

  ```bash
  git status --porcelain        # MUST be empty — abort if not (don't risk the dev's changes)
  ORIG=$(git branch --show-current)   # capture before checkout
  gh pr checkout <n>            # handles forks; permission-prompted
  # ... run the passes ...
  git checkout "$ORIG"         # RESTORE — run even on error (cleanup), see below
  ```

  If the tree is dirty, **stop and tell the developer** rather than checking out. Restore the
  original branch at the **end of the whole run, even on error** — treat it as a cleanup step
  that always executes, so a failed pass never strands the developer on the PR branch.

Report what you gathered (PR intent, linked issue, existing discussion, diff scope) and call
out anything absent (no linked issue, no comments) — absences are noted, never fatal.

### 2. Passes — context first, then three in parallel

Four **read-only** passes, each in its own isolated subagent (Agent tool):

1. **Spawn [`pr-context`](../../agents/pr-context.md) first** — orientation. It surveys the
   touched code area and returns a brief the other passes build on.
2. **Feed its brief into the other three, spawned in PARALLEL** (multiple Agent calls in one
   turn):
   - [`pr-security`](../../agents/pr-security.md) — security audit (wraps `security-scan`).
   - [`senior-review`](../../agents/senior-review.md) — engineering quality. **Instruct it to
     SKIP its security pass** — `pr-security` covers security; don't double-run it.
   - [`pr-tests`](../../agents/pr-tests.md) — test-quality (wraps `writing-tests`).

**Dispatch lean (+ pull).** Hand each pass only what it needs: the **diff scope**, the
**intake context** (PR description, linked issue, comments), the **pr-context orientation
brief**, and the **beads IDs** of its pass's task and the review epic. Tell it explicitly: *you
may pull more on a need-to-know basis via read-only commands (`gh pr diff`, reading a touched
file) or `bd show <id>`.* Don't paste the whole PR or every sibling pass into a dispatch.

Each pass returns findings (severity / where / what / why / suggested comment text) and a
status from [`.claude/references/subagent-status-protocol.md`](../../references/subagent-status-protocol.md).
A pass that finds nothing, or sees an empty/docs-only diff, says so — that's a valid no-op, not
a failure.

### 3. Compile

De-duplicate findings across the four passes (the security and senior passes can land on the
same line) and order them into **one prioritized list** using the shared severity vocab:
**CRITICAL / HIGH / MEDIUM / LOW / INFO**. Keep each finding's file+line anchor and suggested
comment text so the post step can place it.

### 4. Record (beads, dual-mode)

Per [`.claude/references/beads.md`](../../references/beads.md), and as the **single writer** —
only the orchestrator writes beads; the review agents are read-only on it.

- **Beads-enhanced:** record a **review epic** for this PR, **one child task per pass**
  (context / security / senior / tests), and **each finding as a child issue** under its pass's
  task. This makes the review survive a long session.
- **Standalone:** run the same flow conversationally — track the compiled list in-session. No
  errors when `.beads/` is absent.

### 5. Curation gate (human — required)

Walk the compiled list with the developer and decide each item: **keep / drop / edit**. This
gate is mandatory — **nothing is posted without it.** Use `AskUserQuestion` or a plain
walk-through; the point is that only signal the developer endorses lands on the PR. Edited
items carry the developer's wording into the post.

### 6. Post — one batched COMMENT review

If, after curation, **nothing is kept** (or nothing actionable was ever found), **post nothing**
and report that in-session. Never post filler or a verdict.

Otherwise post exactly **one** review. `event` is **always `"COMMENT"`** (see Guardrails):

```bash
gh api --method POST repos/{owner}/{repo}/pulls/<n>/reviews --input payload.json
```

```json
{
  "commit_id": "<headRefOid>",
  "body": "<summary + every non-line-anchored item>",
  "event": "COMMENT",
  "comments": [
    { "path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "<finding>" }
  ]
}
```

- **Inline (line-anchored):** kept **code-related** items become entries in `comments` with
  `path` / `line` / `side`. Multi-line spans use `start_line` / `start_side`; deleted lines use
  `side: "LEFT"`. An anchor must land on a line present in the PR diff hunks.
- **Body:** non-code items (and the overall summary) go in the review `body`.
- **Degrade, never fail:** an item that can't be anchored to a diff line **folds into the
  body** — it is never dropped and never causes the post to fail.

The post is permission-prompted (it isn't in `allowed-tools`) — the developer approves the
actual send.

## Guardrails

These are the point of this skill. Read them as hard constraints, not guidance.

- **NEVER** approve, reject, or request changes. **NEVER** `gh pr merge`, `gh pr close`,
  `gh pr edit`, `gh pr ready`, or `gh pr review --approve|--request-changes`. **NEVER** edit
  the PR title, body, labels, or any PR metadata.
- **NEVER** edit, create, or delete repo content. **NEVER** commit or push. This skill never
  fixes the issues it finds — it reviews and comments only.
- **`event` is ALWAYS `"COMMENT"`.** There is no path in this workflow that submits `APPROVE`
  or `REQUEST_CHANGES`. If you ever find yourself constructing another event value, stop.
- **The ONLY writes this workflow performs are exactly three:**
  1. **beads tracking** (epic / per-pass tasks / per-finding issues),
  2. the **local branch checkout** (`gh pr checkout`, restored to the original branch after),
  3. the **single `event=COMMENT` review**.

  Everything else is read-only.
- **`allowed-tools` stays read-only** so the checkout and the post surface permission prompts —
  the human stays in the loop, and the workflow runs where `--dangerously-skip-permissions` is
  forbidden. Do not widen it to auto-approve the checkout or the post.

### Red flags — STOP

- About to call `gh pr merge` / `close` / `edit` / `ready` / `review --approve` → **stop.**
- Constructing a review payload with `event` other than `"COMMENT"` → **stop.**
- About to `Edit`/`Write` a repo file, commit, or push → **stop.**
- About to post before the curation gate ran → **stop.**
- A subagent offered to apply a fix or post a comment → ignore it; only the orchestrator posts,
  and only after curation.

## Read-only by definition vs. by contract

The review passes are read-only two different ways — a conscious design choice, stated here so
it isn't mistaken for an oversight:

- **Structurally read-only** — [`pr-context`](../../agents/pr-context.md),
  [`pr-security`](../../agents/pr-security.md), and [`pr-tests`](../../agents/pr-tests.md) have
  `tools:` allowlists that **exclude all write capability** (no `Edit`/`Write`, no commit/push,
  no GitHub write subcommands, no raw `gh api` write method, no `Agent`/`AskUserQuestion`).
  They *cannot* edit anything.
- **Contractually read-only** — [`senior-review`](../../agents/senior-review.md) is reused
  as-is. Its skill never edits; this orchestrator dispatches it read-only, asks it only to
  return findings, and never has it fix, post, or record. Do **not** modify `senior-review` to
  fit this workflow — its contract already holds.

Either way, the never-edit guarantee for someone else's PR is preserved: the agents return
findings, the orchestrator owns every outward action.

## Related

- [`validate`](../validate/SKILL.md) — the review gate for **your own** pre-ship code (fixes in
  a loop); `pr-review` is the comment-only review of **someone else's** PR.
- [`security-scan`](../security-scan/SKILL.md) / [`writing-tests`](../writing-tests/SKILL.md) —
  the methodologies the `pr-security` / `pr-tests` passes wrap.
- [`autorun`](../autorun/SKILL.md) — the supervised feature-execution orchestrator this skill's
  structure (lean dispatch, parallel subagents, beads single-writer, permissions-on) mirrors.
- [`.claude/references/subagent-status-protocol.md`](../../references/subagent-status-protocol.md)
  — the statuses every pass returns.
