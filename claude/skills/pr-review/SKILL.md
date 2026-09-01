---
name: pr-review
description: Use when reviewing someone else's GitHub pull request by number — a teammate's PR you were pointed at with "review PR 1234", "check Noah's PR", "do a security pass on #1234". Covers verifying the PR actually works, not just reading the diff. Never approves. Not for reviewing your own pre-ship code (use validate).
allowed-tools: Read Bash(gh pr view *) Bash(gh pr diff *) Bash(gh issue view *) Bash(gh api -X GET *) Bash(gh repo view *) Bash(git status*) Bash(git branch *) Bash(git diff *) Bash(git log *) Bash(git show *) Agent AskUserQuestion
---

# PR Review

A comment-only review of a teammate's GitHub pull request. Point it at a PR number and it
gathers the PR's context, runs a security pass plus a QA pass that **checks the feature actually
works** — along with whatever other passes the PR warrants — compiles the findings into a
**severity table** you review, and posts only the items you pick, **inline on the code they
reference**, with the rest in the review body.

It **never approves, merges, closes, edits, or resolves** anything. Its outward actions are
posting review comments and — only when you explicitly grant it — submitting the review with a
**"Needs changes"** status. Approving is impossible. See [Guardrails](#guardrails).

**Not `validate`.** [`validate`](../validate/SKILL.md) reviews *your own* pre-ship code and
fixes findings in a loop. This reviews *someone else's* PR and never fixes anything — it
verifies, compiles, gates with you, and comments.

## When NOT to use

- Reviewing your own pre-ship change → [`validate`](../validate/SKILL.md).
- You want to approve or merge → this skill never will; do it yourself with `gh`.
- A trivial PR (typo, one-line config) → read it and post one `gh pr comment`; the machinery
  isn't worth it.

## Before you run

- **You are usually already on the PR branch.** The normal entry is `clwt pr <n>`, so the
  session starts in a worktree checked out to the PR's branch. **Verify, don't check out:**

  ```bash
  gh pr view <n> --json headRefName,headRefOid -q '.headRefName + " " + .headRefOid'
  git branch --show-current      # should match headRefName
  ```

  If the current branch matches, review the working tree directly (the QA pass can run tests
  here). If it does **not** match, do **not** switch branches — fall back to reviewing from
  `gh pr diff <n>` and read touched files at the PR's ref; tell the developer the QA pass will
  be diff-only unless they check the branch out.
- **Keep permissions on.** `allowed-tools` is read-only by design. The two consequential
  actions — the QA pass running code, and the final post — surface permission prompts you
  approve. This is what keeps you in the loop. Never route around it.
- **Trust boundary for the QA pass.** Exercising the feature is safe because these are your
  team's PRs in your own repo. If you are ever pointed at a PR from an **untrusted fork**, do not
  run its code — verify by tracing only, and say so.
- GitHub access is the `gh` CLI ([`github-tool-preference`](../../rules/github-tool-preference.md));
  raw `gh api` only where no subcommand exists (posting the review), reads pin `-X GET`.

## The run

### 1. Intake

Pull the PR's own account of itself and the discussion already on it, then read the diff.

```bash
# description, files, existing comments, existing reviews, linked-issue linkage
gh pr view <n> --json number,title,body,headRefName,headRefOid,baseRefName,files,comments,reviews,closingIssuesReferences
gh pr view <n> --comments      # conversation + review-thread comments
gh pr diff <n>                 # the diff reviewers anchor against
```

- **Start from the PR description** — what the author says it does is the claim the QA pass
  verifies. Capture the head commit (`headRefOid`) as the `commit_id` for posting.
- **Read existing comments and reviews.** Note what other reviewers already raised (especially
  anything the author already fixed or a reviewer already approved) so you don't re-post settled
  points. Prefer `closingIssuesReferences[]` for the linked issue; `gh issue view <num>` for its
  intent. Absences (no linked issue, no comments) are noted, never fatal.

Report what you gathered — PR intent, linked issue, existing discussion, diff scope — before the
passes.

### 2. Passes — context first, then the rest in parallel

Every pass is a **read-only reviewer in its own subagent** (Agent tool), except the QA pass,
which runs code. Two passes are **mandatory**; you choose the rest by what the PR touches.

1. **`pr-context` first** — orientation. It surveys the touched area and returns a brief the
   other passes build on (intent, conventions, pre-flagged risks, and an "already settled — do
   not re-raise" list from the existing discussion).
2. **Then, feeding that brief in, spawn in PARALLEL (multiple Agent calls in one turn):**
   - **`pr-security` — ALWAYS.** The security audit is non-negotiable, every review.
   - **`qa-review` — ALWAYS.** The verification pass. Its job is to confirm **the feature
     actually works as the PR claims** — not to re-run the test suites (CI already does that; see
     [The QA pass](#the-qa-pass)). It traces the real code path end to end and, where the feature
     is exercisable in the worktree, **exercises the real behavior** (drives the app, calls the
     endpoint, walks the flow) to see it work. Verdict: **works / broken / not-exercised**, with
     evidence of what it traced and what it actually ran. A not-exercised is an honest result,
     never dressed up as "works".
   - **`senior-review` — usually.** Engineering quality (completeness, correctness, YAGNI).
     **Tell it to SKIP its own security pass** — `pr-security` owns that.
   - **`pr-tests` — when the PR changes behavior or adds logic.** Test-quality: is the changed
     behavior actually covered.
   - **`design-review` — only when the PR touches frontend** (`.tsx/.jsx/.vue/.svelte`, CSS/
     Tailwind, HTML/templates). Dispatch it **static** unless the developer opts into runtime.
     On a non-frontend PR, don't spawn it.

**Dispatch lean.** Hand each pass the diff scope, the intake context, and the `pr-context`
brief; tell it it may pull more read-only on a need-to-know basis. Don't paste the whole PR into
each dispatch. Each pass returns findings as **severity / file:line / what / why / suggested
comment text**.

### 3. Compile → severity table

De-duplicate across passes (security and senior often land on the same line) and order into one
list using **CRITICAL / HIGH / MEDIUM / LOW / INFO**. Fold the QA verdict in as its own
top-line result. Present it to the developer as a **table** for review — this is the surface
they pick from:

| Sev | Finding | Location | Pass | Fix |
|-----|---------|----------|------|-----|
| 🔴 CRITICAL | one-line summary | `file:line` | security | one-line fix |

Add a short **"already raised / cleared — not re-posting"** note for anything the existing
discussion settled, so the developer sees it was considered. An HTML artifact grouped the same
way is optional and fine — but **never post its link to the PR** (it's private; a dead link for
the team).

### 4. Curation gate (required)

Walk the table with the developer: **keep / drop / edit** each item. Nothing is posted without
this. Edited items carry the developer's wording. If nothing is kept, **post nothing** and say
so — never post filler.

**Also settle the review status here.** Default is `COMMENT`. If the findings warrant it you may
**recommend** "Needs changes" — but you post `REQUEST_CHANGES` **only if the developer
explicitly grants it this review.** Silence is not a grant; default to `COMMENT`. **Never**
`APPROVE`.

### 5. Post — one batched review

Post exactly one review. `event` is `COMMENT` (default) or `REQUEST_CHANGES` (only if granted in
the gate).

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

- **Inline first.** Every kept **code-related** item becomes an entry in `comments` with `path`
  / `line` / `side: "RIGHT"` (deleted lines `LEFT`; spans use `start_line`/`start_side`). An
  anchor must land on a line present in the diff hunks — **verify each anchor is in-bounds
  before posting** (a bad anchor 422s the whole call).
- **Body second.** The summary and any item that can't be anchored go in the review `body`. An
  unanchorable item **folds into the body — never dropped, never fails the post.**
- The post is permission-prompted (not in `allowed-tools`) — the developer approves the send.

## The QA pass

This is the reason the skill exists: **do not bless a PR on the assumption that the code works —
confirm the feature actually works and isn't broken or half-wired.**

- **Not a test runner.** The unit / integration / e2e suites already run in the PR's CI on every
  push — re-running them here is redundant and not the point. Read their outcome instead of
  reproducing it: `gh pr checks <n>` tells you whether CI's suites are green. QA's job is the
  thing CI can't tell you — whether the feature actually does what the description claims.
- **Verify the claim, not the diff.** Start from each claim in the PR description and confirm the
  implementation delivers it: the path is wired end to end, the feature is reachable, inputs and
  outputs are what's promised, the obvious edge cases hold. A feature that typechecks and passes
  CI can still be wired to nothing, return the wrong shape, or never be reachable — that is what
  this pass catches.
- **Exercise it where you can.** When the feature is exercisable in the worktree, drive the real
  behavior — hit the endpoint, drive the UI via a browser MCP, walk the actual flow — and report
  what you observed. Observing the feature work beats arguing it should.
- **Frontend-facing feature? Run it and hand it to the developer to see.** When the PR is
  primarily a user-facing UI change, the best verification is the developer's own eyes. Bring up
  the local environment (guide the developer through any interactive or port-claiming steps — the
  app servers usually allow only one worktree at a time), then give them a **numbered
  walkthrough**: the exact URL / route, any login or seed credentials, the steps to reach and
  exercise the feature, and **what correct behavior looks like** at each step (tied to the PR's
  claims), plus the edge cases worth poking. The developer walks it and reports back — their
  verdict is the QA result. You may drive the UI yourself first via a browser MCP to confirm it
  loads and catch an obvious break, but don't substitute your screenshot for their look.
- **Backend / API / CLI feature? Run it and hand the developer the commands.** When the feature
  is an endpoint, job, or command with no UI, exercising it means giving the developer something
  they can run and read. Bring up what it needs locally, then hand them a **copy-pasteable
  sequence** — `curl` / httpie against the local endpoint, the CLI invocation, or a SQL query to
  inspect the resulting state — each with the **expected output**, and any setup (an auth token,
  seed data) spelled out. They can run each with the `!` prefix so the output lands in the
  session. Their observed result is the QA verdict; as with the UI branch, you may run it first
  to pre-check, but the developer seeing the real output is the point.
- **Never launder not-exercised into works.** "Traced and looks correct" and "exercised and
  observed working" are different results and must read differently. If the feature couldn't be
  exercised (needs infra you can't stand up, no reachable entry point), say so — don't upgrade a
  trace into a green.
- The QA verdict leads the severity table as its own line (✅ works / 🔴 broken / ⚠️ not
  exercised), so the developer decides with the verification state in front of them.

## Comment style

Write for a teammate whose first language may not be English.

- **Succinct and literal.** Short sentences. State the problem, the location, the fix. No idioms.
- **No praise sandwich.** Don't open or close with compliments. Lead with the finding.
- **One issue per comment**, anchored to the line it's about.
- **Verdict + fix**, e.g. *"Blocker — `vote` skips the visibility filter, so any member can
  probe request ids. Fix: route it through `findScopedWithDecision`."*

## Guardrails

Hard constraints, not guidance.

- **NEVER approve.** No `gh pr merge`, `gh pr close`, `gh pr ready`, `gh pr edit`, or
  `gh pr review --approve`. There is no code path that submits `event: "APPROVE"`.
- **`event` is `COMMENT` by default; `REQUEST_CHANGES` only on the developer's explicit
  per-review grant** in the curation gate. If you're building a payload with
  `event: "REQUEST_CHANGES"` and the developer didn't just say yes to it, **stop** and default
  to `COMMENT`.
- **NEVER edit, commit, push, or fix** repo content. This skill reviews and comments; it never
  patches what it finds.
- **NEVER resolve, close, or edit a comment thread.** Report what the existing discussion
  settled; don't act on it.
- **NEVER switch the branch out from under the developer.** You're on the PR branch via
  `clwt pr <n>`; if you're not, degrade to diff-only review — don't `git checkout` / `gh pr
  checkout`.
- **The QA pass verifies behavior; it does not re-run CI's test suites.** It traces and, where
  feasible, exercises the feature in the local worktree (trusted team PR), and reads CI status
  rather than reproducing it. Never exercise an untrusted fork's code.
- **Nothing posts before the curation gate.** Only the developer's kept items land.
- **Never post the private review artifact's link to the PR.**

### Red flags — STOP

- About to `gh pr merge` / `close` / `edit` / `ready` / `review --approve` → **stop.**
- Building a payload with `event: "APPROVE"`, or `REQUEST_CHANGES` without an explicit grant →
  **stop.**
- About to resolve / close / mark-outdated a thread → **stop;** the discussion is reported, not
  acted on.
- About to `git checkout` / `gh pr checkout` to a different branch → **stop;** review from the
  diff instead.
- About to re-run the full unit / integration / e2e suite in the QA pass → **stop;** CI already
  runs it — read `gh pr checks` instead, and spend the pass on whether the feature works.
- About to summarize the QA pass as "works" when the feature was only traced, never exercised →
  **stop;** report not-exercised honestly.
- About to `Edit`/`Write` a repo file, commit, or push → **stop.**
- About to post before the curation gate → **stop.**
- A subagent offered to apply a fix or post a comment → ignore it; only the orchestrator posts,
  and only after curation.

## Related

- [`validate`](../validate/SKILL.md) — the review gate for **your own** pre-ship code.
- [`qa-review`](../qa-review/SKILL.md) — the verification methodology the QA pass runs.
- [`security-scan`](../security-scan/SKILL.md) / [`writing-tests`](../writing-tests/SKILL.md) /
  [`design-review`](../design-review/SKILL.md) — the methods the security / test / frontend
  passes wrap.
