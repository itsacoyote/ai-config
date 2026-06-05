---
name: pr-review
description: Use when reviewing someone else's GitHub pull request by number and posting the review back — a comment-only, multi-lens review that never approves, rejects, requests changes, merges, edits, or resolves anything. Re-running on a revised PR is auto-detected as a follow-up. Distinct from validate (which reviews your own pre-ship code). Run from the main session.
disable-model-invocation: true
argument-hint: "<pr-number> [deep|light]"
allowed-tools: Read Bash(gh pr view *) Bash(gh pr diff *) Bash(gh issue view *) Bash(gh api -X GET *) Bash(gh repo view *) Bash(git status*) Bash(git branch *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(bd *) Agent
---

# PR Review

A developer-invoked, comment-only review of a GitHub pull request. Point it at a PR number and
it gathers the PR's full context, checks the branch out locally, runs the read-only review
passes in isolated subagents (a conditional frontend pass joins on frontend PRs), compiles
their findings into one prioritized list, walks that
list with you, and posts the kept items as a **single `event=COMMENT` review** — inline where
they concern code, in the body where they don't.

**Re-running it is the same command.** The first run on a PR is a full review (the behavior
above). When you run `/pr-review <n>` again on a PR that has moved on, it auto-detects a
**follow-up** from your own prior comments — suppressing findings you already raised, reporting
the fate of each prior thread, and surfacing only genuinely-new issues. Every Nth run (or on
`deep`) it does a thorough **deep re-check** instead. State lives on GitHub, so this works from
any machine or session; beads, when present, adds richer memory. See
[Iterative runs](#iterative-runs-follow-up--deep-re-check).

It is **structurally incapable of approving, rejecting, requesting changes, merging, closing,
editing, or resolving threads** on the PR, the repo, or any code. Its only outward actions are
posting comments and threaded replies. See the [Guardrails](#guardrails) section — it is the
centerpiece of this skill, not an afterthought.

**This is not `validate`.** [`validate`](../validate/SKILL.md) reviews **your own** pre-ship
code and fixes findings in a loop before shipping. `pr-review` reviews **someone else's** PR and
**never fixes anything** — it compiles, gates with you, and posts comments. Different target,
different posture: one patches, this one only comments.

## When NOT to use

- Reviewing your own pre-ship change — use [`validate`](../validate/SKILL.md).
- You want to approve, request changes, or merge a PR — this skill will never do that; do it
  yourself with `gh`.
- A trivial PR (typo, one-line config) — a direct read and a manual `gh pr comment` is enough;
  the multi-pass machinery isn't worth it.

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
  only where a subcommand doesn't exist (posting the review; inline review-thread comments and
  replies), and reads pin the method (`gh api -X GET …`).
- **Optional mode override** (`argument-hint: "<pr-number> [deep|light]"`): pass `deep` to force
  a no-suppression deep re-check, `light` to force a light follow-up, or ask for a clean full
  review. Without an override the mode is auto-detected (see
  [Iterative runs](#iterative-runs-follow-up--deep-re-check)).

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

### 2. Detect mode and run number

Decide **first run vs. follow-up** from GitHub — no local state. Resolve your authenticated
identity, then look for your own prior review activity on this PR:

```bash
ME=$(gh api -X GET user --jq .login)        # your gh login — the identity that owns prior comments

# your prior review objects on the PR (top-level reviews you submitted)
gh api -X GET repos/{owner}/{repo}/pulls/<n>/reviews \
  --jq "[.[] | select(.user.login == \"$ME\")]"

# ALL inline review-thread comments (carry id, user, path, position, in_reply_to_id, body).
# Fetch the full list — you need others' replies for the fate report, not just your own.
ALL=$(gh api -X GET repos/{owner}/{repo}/pulls/<n>/comments)
# your prior comments: the ones the suppression + still-stands checks key off
echo "$ALL" | jq "[.[] | select(.user.login == \"$ME\")]"
```

Derive both views from `ALL`: **your** prior comments (`select(.user.login == "$ME")`) drive
suppression and the still-stands/outdated checks; **others'** replies
(`in_reply_to_id` pointing at one of your comment ids, `user.login != "$ME"`) drive the
**author-replied** fate. Don't re-fetch a filtered-to-you list — it discards the replies.

- **No prior review objects → first run.** Proceed exactly as today: a full review, no
  suppression. The rest of this skill's first-run behavior is unchanged.
- **Some prior review objects → follow-up.** **Run number = (count of your prior review
  objects) + 1.** Default mode is **light follow-up**; every **Nth run (default N = 3)** is a
  **deep re-check** instead (run 3, 6, 9, …).
- **Launch override wins over auto-detect.** `deep` forces a deep re-check; `light` forces a
  light follow-up; the developer can also ask for a clean full review (treat as a first run).
  Use an override when auto-detect is wrong — e.g. your prior comments were unrelated chatter.

**Announce the detected mode and run number before the passes**, so the developer can correct
it — e.g. *"Follow-up review, run #2 (light), you have 5 prior comments on this PR — say `deep`
for a full re-check."* On a first run, say so plainly.

See [Iterative runs](#iterative-runs-follow-up--deep-re-check) for how the mode shapes
suppression, the fate report, and curated replies. The passes themselves are **unchanged** in
every mode — the difference is what the orchestrator does with their findings.

### 3. Passes — context first, then the rest in parallel

The **read-only** passes, each in its own isolated subagent (Agent tool):

1. **Spawn [`pr-context`](../../agents/pr-context.md) first** — orientation. It surveys the
   touched code area and returns a brief the other passes build on.
2. **Feed its brief into the others, spawned in PARALLEL** (multiple Agent calls in one turn):
   - [`pr-security`](../../agents/pr-security.md) — security audit (wraps `security-scan`).
   - [`senior-review`](../../agents/senior-review.md) — engineering quality. **Instruct it to
     SKIP its security pass** — `pr-security` covers security; don't double-run it.
   - [`pr-tests`](../../agents/pr-tests.md) — test-quality (wraps `writing-tests`).
   - [`design-review`](../../agents/design-review.md) — **conditional frontend pass, only
     when the PR touches frontend** (component/markup/style files — `.tsx/.jsx/.vue/.svelte`,
     CSS/Tailwind, HTML/templates). On a non-frontend PR it is simply **not spawned** (and if
     spawned anyway, it no-ops with "No frontend changes — nothing to review"). It reviews
     frontend quality, design-system correctness, component architecture, cross-component
     state/data flow, UX, and accessibility (wraps `design-review` + `frontend-ui-engineering`).
     **Dispatch it in STATIC mode by default** — `pr-review` reviews someone else's PR, so it
     must **never auto-run an untrusted PR's app, dev server, build, or deps.** Static review
     works from the diff, source, and markup only; **runtime (driving the app via a browser MCP —
     Chrome DevTools or Playwright) is an explicit developer opt-in, never automatic.** Pass it the
     runtime-vs-static instruction explicitly (static unless the developer opted in) — the
     agent does not decide its own mode.

**Dispatch lean (+ pull).** Hand each pass only what it needs: the **diff scope**, the
**intake context** (PR description, linked issue, comments), the **pr-context orientation
brief**, and the **beads IDs** of its pass's task and the review epic. Tell it explicitly: *you
may pull more on a need-to-know basis via read-only commands (`gh pr diff`, reading a touched
file) or `bd show <id>`.* Don't paste the whole PR or every sibling pass into a dispatch.

Each pass returns findings (severity / where / what / why / suggested comment text) and a
status from [`.claude/references/subagent-status-protocol.md`](../../references/subagent-status-protocol.md).
A pass that finds nothing, or sees an empty/docs-only diff, says so — that's a valid no-op, not
a failure.

### 4. Compile (and, on a follow-up, suppress)

De-duplicate findings across the passes (the security and senior passes can land on the
same line; the design pass, when it ran, on a frontend file) and order them into **one
prioritized list** using the shared severity vocab:
**CRITICAL / HIGH / MEDIUM / LOW / INFO**. Keep each finding's file+line anchor and suggested
comment text so the post step can place it.

On a **light follow-up**, then apply suppression — see
[Iterative runs](#iterative-runs-follow-up--deep-re-check):

- Drop findings that **conservatively near-duplicate** a comment you already posted (verbatim
  or near-verbatim restatement of the same issue at the same place). This is deliberately
  cautious: **two *distinct* issues at the same location both survive.**
- **Beads-enhanced:** also drop findings matching ones you previously **dropped** in curation
  (remembered drop-decisions), so the developer isn't re-asked about something they declined.
- Keep the suppressed items aside for the run record; don't silently lose them.

On a **deep re-check** (or a first/full run), apply **no suppression** — every finding flows to
curation, including restatements of prior comments. Compile the **fate report** (next section)
on any follow-up regardless of mode.

### 4a. Fate report (follow-up only)

For each of your prior review-thread comments, classify and report its fate from the data
fetched in step 2:

- **outdated** — its `position` is `null` (GitHub couldn't re-anchor it: the code changed, so
  it was likely addressed or moved).
- **author-replied** — a later comment's `in_reply_to_id` points at it, from someone other
  than you.
- **still-stands** — the anchor is intact (`position` non-null) and no one replied.

Surface this as a short table before the curation gate. It's a **read-only** report — never a
trigger to resolve, close, or edit a thread.

### 5. Record (beads, dual-mode)

Per [`.claude/references/beads.md`](../../references/beads.md), and as the **single writer** —
only the orchestrator writes beads; the review agents are read-only on it.

- **Beads-enhanced:** record a **review epic** for this PR (one per PR — reuse it across runs),
  **one child task per pass** (context / security / senior / tests, plus design when the
  frontend pass ran), and **each finding as a child issue** under its pass's task. On a follow-up, also add a **session record** child for
  this run (mode = light/deep, run number, findings, what was posted, what was dropped) and
  carry forward **remembered drop-decisions** so future light runs can suppress them. This makes
  the review survive a long session and across sessions/machines.
- **Standalone:** run the same flow conversationally — track the compiled list in-session, and
  follow-up suppression works off your **posted** comments from GitHub (no remembered drops
  without beads). No errors when `.beads/` is absent.

### 6. Curation gate (human — required)

Walk the (suppressed, on a light follow-up) compiled list with the developer and decide each
item: **keep / drop / edit**. This gate is mandatory — **nothing is posted without it.** Use
`AskUserQuestion` or a plain walk-through; the point is that only signal the developer endorses
lands on the PR. Edited items carry the developer's wording into the post.

**Curated thread replies (opt-in).** On a follow-up, the developer may also choose to reply to
one of their prior threads (e.g. *"this still stands"* on a still-standing thread the author
didn't address). A reply is composed and posted **only if kept in this gate** — never
automatically. Replies post as threaded `in_reply_to` comments (see Post). **A reply never
resolves or closes the thread** — resolving is done by the developer in the GitHub UI.

### 7. Post — one batched COMMENT review (+ any curated replies)

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

**Curated replies (follow-up only).** Any thread reply kept in curation posts as a threaded
comment via `in_reply_to` (one POST per reply, each separately permission-prompted):

```bash
gh api --method POST repos/{owner}/{repo}/pulls/<n>/comments \
  -f body='<your reply>' -F in_reply_to=<prior_comment_id>
```

This adds a comment to an existing thread. It **never** resolves or closes the thread, and only
runs for replies the developer kept in the gate.

Both the review POST and the reply POST are permission-prompted (neither is in `allowed-tools`)
— the developer approves each actual send.

## Iterative runs (follow-up & deep re-check)

Re-running `/pr-review <n>` on a PR that has moved on is the same command — the mode is
auto-detected in [step 2](#2-detect-mode-and-run-number) from your own prior review comments on
GitHub (resolved via your `gh` login), so it works in any new session or on any machine.

| Mode | When | Suppression | Use for |
|---|---|---|---|
| **First / full** | no prior review objects, or override to a clean review | none | the original full review |
| **Light follow-up** | default re-run | near-duplicates of your posted comments (and, with beads, your remembered drops) | "show me only what's genuinely new" |
| **Deep re-check** | every Nth run (default **N = 3**), or `deep` override | **none** — surfaces everything, including restatements | the periodic thorough sweep that catches what earlier rounds missed |

- **The passes are identical in every mode.** They review the current full diff; the mode
  only changes what the orchestrator does with the compiled findings (suppress or not) and
  whether it builds a fate report. Never modify the agents to fit a mode.
- **Suppression is conservative LLM judgment.** Suppress only a verbatim / near-verbatim
  restatement of a comment you already posted at the same place. When in doubt, **keep it** —
  the curation gate is the safety net, and two *distinct* issues at one line both survive.
- **Deep mode relaxes suppression, never guardrails.** A deep re-check still posts a single
  `event=COMMENT` review, never resolves a thread, and never touches PR state — the
  [Guardrails](#guardrails) hold identically in every mode.
- **Dual-mode memory.** GitHub-only is fully functional: follow-up suppression works off your
  posted comments, and run number / fate come straight from the API. Beads-enhanced adds a
  per-PR review epic, a per-run session record (mode, findings, posted, dropped), and remembered
  drop-decisions so light runs also suppress what you previously declined. Detect beads mode
  first ([`.claude/references/beads.md`](../../references/beads.md)); never error without it.

## Guardrails

These are the point of this skill. Read them as hard constraints, not guidance.

- **NEVER** approve, reject, or request changes. **NEVER** `gh pr merge`, `gh pr close`,
  `gh pr edit`, `gh pr ready`, or `gh pr review --approve|--request-changes`. **NEVER** edit
  the PR title, body, labels, or any PR metadata.
- **NEVER** edit, create, or delete repo content. **NEVER** commit or push. This skill never
  fixes the issues it finds — it reviews and comments only.
- **NEVER auto-run an untrusted PR's app.** The conditional design pass is **static by
  default** — it reviews from the diff, source, and markup, and does **not** run the PR's app,
  dev server, build, or install its deps. Runtime evaluation (driving the app via a browser MCP —
  Chrome DevTools or Playwright) is an **explicit developer opt-in only**, never automatic. Reviewing someone
  else's PR must never execute their untrusted code without the developer choosing to.
- **NEVER resolve, close, or edit a comment thread.** Follow-up runs only *report* each prior
  thread's fate and may *add* a curated reply — they never mark a thread resolved or outdated.
  Resolving is the developer's, done in the GitHub UI.
- **`event` is ALWAYS `"COMMENT"`** — in first, light, and **deep** runs alike. There is no
  path in this workflow that submits `APPROVE` or `REQUEST_CHANGES`; deep mode relaxes
  suppression, not guardrails. If you ever find yourself constructing another event value, stop.
- **The ONLY writes this workflow performs are exactly four:**
  1. **beads tracking** (epic / per-pass tasks / per-finding issues / per-run session record),
  2. the **local branch checkout** (`gh pr checkout`, restored to the original branch after),
  3. the **single `event=COMMENT` review**,
  4. **curated `in_reply_to` thread replies** the developer kept in the gate (never auto, never
     resolving the thread).

  Everything else is read-only.
- **`allowed-tools` stays read-only** so the checkout, the review post, and the reply post
  surface permission prompts — the human stays in the loop, and the workflow runs where
  `--dangerously-skip-permissions` is forbidden. The review POST and the reply POST are
  **deliberately kept out** of the allowlist. Do not widen it to auto-approve the checkout, the
  post, or the reply.

### Red flags — STOP

- About to call `gh pr merge` / `close` / `edit` / `ready` / `review --approve` → **stop.**
- Constructing a review payload with `event` other than `"COMMENT"` (including in deep mode) →
  **stop.**
- About to resolve, close, or mark-outdated a comment thread → **stop;** fate is reported, not
  acted on.
- About to post a thread reply that wasn't kept in the curation gate, or to post automatically →
  **stop.**
- About to `Edit`/`Write` a repo file, commit, or push → **stop.**
- About to run the PR's app, dev server, build, or install its deps for the design pass without
  an explicit developer opt-in → **stop;** the design pass is static by default, runtime is
  opt-in only.
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
- **Contractually read-only** — [`senior-review`](../../agents/senior-review.md) and the
  conditional [`design-review`](../../agents/design-review.md) frontend pass are reused as-is.
  Their skills never edit; this orchestrator dispatches them read-only, asks them only to
  return findings, and never has them fix, post, or record. Do **not** modify either agent to
  fit this workflow — their contracts already hold.
  - `design-review` is **not** structurally tool-locked (in runtime mode it can drive a
    browser), so here it carries an extra contractual rule: **dispatch it in static mode by
    default** — it must **never auto-run an untrusted PR's app**; runtime is an explicit
    developer opt-in only. Its findings flow through the same **compile → dedupe → curate →
    post** pipeline as every other pass — it **never posts directly**; the orchestrator turns
    kept findings into curated comments.

Either way, the never-edit guarantee for someone else's PR is preserved: the agents return
findings, the orchestrator owns every outward action.

## Related

- [`validate`](../validate/SKILL.md) — the review gate for **your own** pre-ship code (fixes in
  a loop); `pr-review` is the comment-only review of **someone else's** PR.
- [`security-scan`](../security-scan/SKILL.md) / [`writing-tests`](../writing-tests/SKILL.md) /
  [`design-review`](../design-review/SKILL.md) — the methodologies the `pr-security` /
  `pr-tests` / conditional design passes wrap.
- [`autorun`](../autorun/SKILL.md) — the supervised feature-execution orchestrator this skill's
  structure (lean dispatch, parallel subagents, beads single-writer, permissions-on) mirrors.
- [`.claude/references/subagent-status-protocol.md`](../../references/subagent-status-protocol.md)
  — the statuses every pass returns.
