---
name: standup
description: Use when returning from a break, a night, or a weekend and you want a read-only recap of recent work — what got done, what's in progress, and what to pick up next — formatted for a standup. Pulls from beads when available, otherwise git history, PRs, and notes.
disable-model-invocation: true
argument-hint: "[time window, e.g. 24h, 3d, since friday]"
allowed-tools: Read Bash(git log *) Bash(git status*) Bash(git diff *) Bash(git branch *) Bash(git stash list*) Bash(gh pr list *) Bash(gh pr view *) Bash(gh issue list *) Bash(gh run list *) Bash(bd *)
---

# Standup

Reconstruct what's happened recently and present it as a standup-ready briefing — so you can catch up after time away and say, in a meeting, what you did, what's in flight, and what's next.

**This is strictly read-only.** Never edit, commit, close, claim, push, or change anything — not a file, not a beads issue, not a branch. You are gathering and summarizing existing state only. If you're tempted to "tidy up" something you notice, mention it in the report instead.

## When NOT to use

- Mid-task, when you already hold the context — this is for *regaining* lost context, not narrating work you're in the middle of.
- As a substitute for the real workflow steps — it reports on work, it doesn't plan or do it.

## The time window

Default to the **last 24 hours**. The window is arbitrary — honor whatever the user passes as an argument (`24h`, `3d`, `since friday`, `last week`) and translate it to the right flags (`git log --since=...`, etc.). If a weekend or holiday sits in the window, widen to the last working session rather than reporting "nothing happened." State the window you used at the top of the report.

## Gathering the picture

Pull from the richest source available. **Check for beads first**, then fill gaps with git, PRs, and notes. Cross-reference — a closed beads issue plus its commits tells a fuller story than either alone.

### 1. Beads

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`sh .claude/references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

Beads is the primary source of truth. Read (never mutate):

- **Done** — issues closed within the window. Check `bd --help` / `bd list --help` for a status + time filter; fall back to `bd list` and read the timestamps.
- **In progress** — issues currently `in_progress` (where you left off), and any `blocked` ones with their blockers.
- **Next** — `bd ready` for unblocked issues ready to pick up, highest priority first.
- Open `bd show <id>` on the few most relevant issues for titles and context. Don't invent IDs — read them from `bd` output.

### 2. Git — what was actually written

Works in every project, beads or not:

- **Commits in the window**, across branches: `git log --all --since="<window>" --author="<you>" --pretty=...`. Group by branch. These are the concrete "what got done."
- **Where you left off**: current branch (`git branch --show-current`), uncommitted changes (`git status -s`), stashes (`git stash list`), and unpushed commits (`git log @{u}.. ` or compare against the remote). This is the real "in progress."
- Skim `git diff --stat` on uncommitted work to describe it without dumping the diff.

### 3. Pull requests (if `gh` is available and authed)

- **Open PRs** you authored: `gh pr list --author "@me" --state open` — status, review state, CI.
- **Recently merged**: `gh pr list --author "@me" --state merged --search "merged:>=<date>"` — done work that's landed.
- **Review requests waiting on you**: `gh pr list --search "review-requested:@me"` — a "next" item and a potential blocker for others.
- Optionally `gh run list` for the state of recent CI on your branch.

### 4. Notes and context on hand

If the project surfaces other recent signal — a memory/MEMORY index, a changelog, TODOs touched in the window — fold in anything that clarifies *why* the work happened. Label inferences as inferences; don't present a guess as fact.

## The report

Format as a clean, skimmable standup briefing. Lead with the window and a one-line orientation, then the three classic buckets, then blockers. Keep it tight — this is a catch-up, not a transcript.

```markdown
## Standup — <window, e.g. last 24h> · <date>

_Orientation: one line on the headline of the period (e.g. "shipped the auth
refactor PR, mid-way through the rate-limiter")._

### ✅ Done
- <completed work — closed issues / merged PRs / landed commits, in plain language>

### 🚧 In progress / where you left off
- <current branch, uncommitted or stashed work, in-progress issues>
- <the single most useful "you were here" pointer to resume fast>

### ⏭️ Next / ready to pick up
- <ready beads issues, open PRs awaiting action, review requests, obvious follow-ups>

### ⛔ Blockers / waiting on
- <blocked issues, failing CI, PRs awaiting others — omit the section if none>
```

Adapt to what you found: drop a bucket that's genuinely empty (note it briefly rather than padding), and if there's no signal at all in the window, say so plainly and suggest widening it. Translate issue IDs and commit hashes into human descriptions — the user wants to *talk* about this, not read a log.

## Guardrails

- **Read-only, always.** No writes of any kind. If `bd`, `git`, or `gh` would mutate, don't run it.
- **Don't fabricate.** If a source is unavailable (no `gh` auth, no beads, shallow clone), say what you couldn't check rather than guessing.
- **Attribute to the user where it matters** — filter to their commits/PRs for "what *I* did," but note significant work by others in the same window when it affects what they pick up next.
