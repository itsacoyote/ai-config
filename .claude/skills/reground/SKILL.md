---
name: reground
description: Use when starting or switching to new work in a long-lived or /cleared session, or when you're unsure which worktree/branch you're in, whether the tree is clean, or where in-progress work actually lives. Read-only orientation across all worktrees, ending in a verdict on where the new work should go. Personal, developer-invoked.
disable-model-invocation: true
argument-hint: "[optional: what you're about to work on]"
allowed-tools: Read Bash(bash ${CLAUDE_SKILL_DIR}/../../scripts/worktree-status.sh*) Bash(git worktree list*) Bash(git status*) Bash(git branch*) Bash(git log *) Bash(git stash list*) Bash(gh pr view*) Bash(gh pr list*)
---

# Reground

Re-establish *where you are* before touching code — which worktree, which branch, whether the tree is clean, and what the other worktrees are doing. Then give a verdict on where the new work should go.

**Strictly read-only.** Never stash, commit, branch, checkout, or kill a server here. You surface state and *recommend* the next command; the developer runs it. Inform, don't gate.

## Gather (run the script)

```bash
bash ${CLAUDE_SKILL_DIR}/../../scripts/worktree-status.sh          # where am I, all worktrees, tree state
```

The script resolves relative to its own location, so it always reports the worktree you're actually in — not a hardcoded checkout.

## The verdict

From what the script reports, tell the developer plainly and skimmably:

1. **Where they are** — worktree + branch + clean/dirty, in one line.
2. **Whether this is the right place** for the work in the argument (if one was given):
   - On `main` or a clean throwaway → fine to branch here.
   - On a **mid-flight feature branch** and the new work is *unrelated* → recommend a **fresh worktree** (`git worktree add <path> -b <branch>`) rather than recycling this one. This is the core habit that keeps long-lived sessions clean: **one worktree = one feature**.
   - **Dirty tree** → recommend committing or stashing *first*; name the files so they can decide.
   - Branch **already merged** (confirm with `gh pr view` if useful) → the worktree is spent; suggest tearing it down (`git worktree remove`) and starting fresh.

Keep it to a short briefing plus the one or two commands to run next. Do **not** run them.
