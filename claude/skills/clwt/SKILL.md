---
name: clwt
description: Use when the developer asks to create, open, list, or tear down a git worktree, or wants a Claude session running in one — and whenever you are about to reach across directories with `git -C`. Explains the clwt CLI and why the launching subcommands must be run by the developer, not by Claude.
---

# clwt

`clwt` manages this repository's worktrees and launches Claude Code inside them. It lives at
`.claude/scripts/clwt` and installs onto the developer's `PATH` with `clwt install`.

## You are already in the right worktree — use plain git

**Never use `git -C <path>`.** When a session was started by `clwt`, its working directory *is*
the worktree it is meant to operate on. `git status`, `git add`, `git commit` all act on the
right tree with no path argument. Reaching across directories re-derives a path on every call,
silently succeeds against the wrong tree when that path is stale, and makes every relative path
a skill computes wrong.

`Bash(git -C *)` is in `permissions.deny` in `.claude/settings.json`, so the call will be
blocked. That rule removes the habit's default spelling, not the capability —
`git --git-dir=… --work-tree=…` and `cd <path> && git …` still work and are not denied. Treat
the rule as a reminder that reaching across directories means something has gone wrong upstream,
not as a wall to route around. If you genuinely believe you need another worktree's state, say
so and let the developer decide.

To find out where you are, use the `reground` skill or
`bash .claude/scripts/worktree-status.sh` — both report across all worktrees with plain git.

## You cannot run the launching subcommands

`claude` has no "start in directory" flag; it inherits its working directory from whatever
launched it. So `clwt` works by `cd`-ing into the target and `exec`-ing `claude` there — which
only a shell outside Claude can do. **Claude cannot relaunch itself into a new directory.**

For `new`, `branch`, `open`, `pr`, and `root`, your job is to **recommend the exact command** and
let the developer run it. Do not try to run them yourself, and do not simulate them with
`git worktree add` — a worktree made that way is unmanaged, missing the `.worktreeinclude` copy,
and `clwt` will decline to manage it later.

`list`, `remove`, and `prune` do not launch anything, so you may run those when asked.

## Commands

| Command | What it does |
|---|---|
| `clwt` / `clwt list` | list this repository's managed worktrees, flagging unmanaged ones |
| `clwt new <type>/<slug>` | branch from the *current* origin default, create the worktree, launch |
| `clwt branch <branch>` | check out an existing local or origin branch, launch |
| `clwt open <branch>` | launch in an existing managed worktree |
| `clwt pr <number>` | check a pull request out into a worktree, launch |
| `clwt root` | launch in the primary checkout |
| `clwt remove <branch> [--delete-branch]` | remove a clean managed worktree |
| `clwt prune [--yes]` | sweep worktrees whose branch has an already-merged PR; dry run without `--yes` |
| `clwt install` | symlink onto `PATH` |

`--yolo` on any launching subcommand adds `--dangerously-skip-permissions`. Arguments after `--`
pass through to `claude`: `clwt new feat/x --yolo -- --model opus`.

Worktrees live at `~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`.

## What to recommend, when

- **Starting unrelated work** while on a mid-flight branch → `clwt new <type>/<slug>`. One
  worktree = one feature; don't recycle.
- **Returning to existing work** → `clwt branch <branch>`, or `clwt open <branch>` if the
  worktree already exists.
- **Branch already checked out somewhere** → `clwt` handles it: it reuses a managed worktree,
  and refuses with a distinct message when the branch is in the primary checkout (use
  `clwt root`) or in an unmanaged worktree.
- **Branch merged** → `clwt remove <branch>`, or `clwt prune` to sweep everything merged at once.

## The issue tracker stays central

Every `clwt`-launched session gets `CLWT_REPO_ROOT` pointing at the primary checkout, so a
tracker can find its one database there.

`bd` does not need it — it resolves through the git common dir already — but the rule that makes
that work still binds: **never `bd init` in a worktree, and never copy `.beads/` into one.**
`clwt` refuses to copy `.beads/` even when `.worktreeinclude` matches it. See
[`../../references/beads.md`](../../references/beads.md).

## When NOT to use

- **Single-worktree repositories**, or a quick edit on the branch you are already on. Making a
  worktree for a two-line fix is overhead.
- **Repositories without an `origin` remote** — `clwt` derives its paths from it and will refuse.
- **Deciding *where you are*** — that is `reground`'s job. This skill is about acting on that
  answer, not producing it.
- **Any worktree outside the managed root.** `clwt` deliberately will not touch those; use plain
  git and expect none of clwt's guarantees.
