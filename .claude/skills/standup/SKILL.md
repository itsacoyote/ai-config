---
name: standup
description: Use when returning from a break, a night, or a weekend and you want a read-only recap of recent work — what got done, what's in progress, and what to pick up next — formatted for a standup. Requires beads; cross-references git history, PRs, and notes.
disable-model-invocation: true
argument-hint: "[time window, e.g. 24h, 3d, since friday]"
allowed-tools: Read Bash(sh ${CLAUDE_SKILL_DIR}/scripts/standup-gather.sh*) Bash(bash ${CLAUDE_SKILL_DIR}/scripts/standup-gather.sh*) Bash(git log *) Bash(git status*) Bash(git diff *) Bash(git branch *) Bash(git stash list*) Bash(gh pr list *) Bash(gh pr view *) Bash(gh issue list *) Bash(gh run list *) Bash(bd *)
---

# Standup

Reconstruct what's happened recently and present it as a standup-ready briefing — so you can catch up after time away and say, in a meeting, what you did, what's in flight, and what's next.

**This is strictly read-only.** Never edit, commit, close, claim, push, or change anything — not a file, not a beads issue, not a branch. You are gathering and summarizing existing state only. If you're tempted to "tidy up" something you notice, mention it in the report instead.

## When NOT to use

- Mid-task, when you already hold the context — this is for *regaining* lost context, not narrating work you're in the middle of.
- As a substitute for the real workflow steps — it reports on work, it doesn't plan or do it.

## Gathering the picture (run the script)

Run the gather script — it does the deterministic, **read-only** collection so you don't re-derive the commands. Pass the time window as its argument (default: last 24h):

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/standup-gather.sh                 # last 24h
sh ${CLAUDE_SKILL_DIR}/scripts/standup-gather.sh 3d              # 24h / 3d / 2w
sh ${CLAUDE_SKILL_DIR}/scripts/standup-gather.sh "since friday"  # or a phrase: "last week", "yesterday"
```

**Beads is required.** The script gates on it (via `beads-preflight.sh`) and **exits non-zero if beads isn't set up** — if that happens, **stop** and tell the user to run the `setup-beads` skill, then retry. It does not produce a beads-less recap.

When beads is present it dumps, in labeled sections (all read-only — nothing is mutated):

- **BEADS** — closed issues (Done candidates), `in_progress` (where you left off), `blocked` with blockers, and `bd ready` (Next). Cross-reference a closed issue with its commits for the fuller story; don't invent IDs — read them from the output.
- **GIT** — commits in the window across branches (filtered to you), current branch, working-tree status, stashes, unpushed commits, and the uncommitted diffstat. The concrete "what got done" and the real "in progress."
- **PULL REQUESTS / CI** — your open PRs, recently merged (with `mergedAt`), review requests waiting on you, and recent CI runs. Skipped with a note if `gh` is missing or unauthed.

Two things the script leaves to you:

- **Window edge cases.** It passes the window straight to git and computes a cutoff for relative windows; `bd` closed and `gh` merged are dumped recent-with-timestamps, so **filter those to the window** during synthesis (the script's header says which). If a weekend or holiday sits in the window and the result is empty, **widen to the last working session** and re-run rather than reporting "nothing happened."
- **Notes / "why".** Fold in other recent signal the script doesn't gather — a changelog, a memory index, TODOs touched in the window — anything that clarifies *why* the work happened. Label inferences as inferences; don't present a guess as fact.

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

- **Read-only, always.** The gather script is read-only by construction (it runs only `bd`/`git`/`gh` read commands); keep it that way and never add a write. Any tidying you're tempted to do goes in the report as a suggestion, not an action.
- **Don't fabricate.** If a source is unavailable (no `gh` auth, shallow clone), say what you couldn't check rather than guessing. (Missing beads stops the run entirely — it doesn't degrade.)
- **Attribute to the user where it matters** — filter to their commits/PRs for "what *I* did," but note significant work by others in the same window when it affects what they pick up next.
