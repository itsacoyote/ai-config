---
name: reground
description: Use when starting or switching to new work in a long-lived or /cleared session, or when you're unsure which worktree/branch you're in, whether the tree is clean, or where in-progress work actually lives. Read-only orientation across all worktrees, ending in a verdict on where the new work should go. Personal, developer-invoked.
argument-hint: "[optional: what you're about to work on]"
metadata:
  category: git-maintenance
---

# Reground

Re-establish *where you are* before touching code — which worktree, which branch, whether the tree is clean, and what the other worktrees are doing. Then give a verdict on where the new work should go.

**Strictly read-only.** Never stash, commit, branch, checkout, or kill a server here. You surface state and *recommend* the next command; the developer runs it. Inform, don't gate.

## Gather (run the script)

Resolve `../../scripts/worktree-status.sh` from this skill directory, then run the resulting absolute path from the checkout you want to inspect:

```text
bash <library-root>/scripts/worktree-status.sh
```

The script inspects its current working directory, so launch it from the target checkout rather than a hardcoded or ambient path.

## The verdict

From what the script reports, tell the developer plainly and skimmably:

1. **Where they are** — worktree + branch + clean/dirty, in one line.
2. **Whether this is the right place** for the work in the argument (if one was given):
   - On `main` or a clean throwaway → fine to branch here.
   - On a **mid-flight feature branch** and the new work is *unrelated* → recommend a **fresh worktree** (`git worktree add <path> -b <branch>`) rather than recycling this one. This is the core habit that keeps long-lived sessions clean: **one worktree = one feature**.
   - **Dirty tree** → recommend committing or stashing *first*; name the files so they can decide.
   - Branch **already merged** (confirm with `gh pr view` if useful) → the worktree is spent; suggest tearing it down (`git worktree remove`) and starting fresh.

Keep it to a short briefing plus the one or two commands to run next. Do **not** run them.
