# `clwt` — worktree CLI

A small Bash CLI at `claude/scripts/clwt` that manages this repository's git
worktrees and launches Claude Code inside them. **You run it from your shell, not
from inside Claude.**

**Prerequisites:** stock macOS `bash` 3.2+ and `git`. `gh` (authenticated) is needed only by `clwt pr`
and `clwt prune` — both fail with a clear message rather than guessing if it is missing
or logged out. The repository must have an `origin` remote, since the managed paths are
derived from it. The network steps of `clwt new` and `clwt branch`, and `clwt pr`'s base-branch fetch, over an SSH remote
run ssh in batch mode with a connect timeout, so an unreachable remote fails with git's
own error instead of hanging; batch mode also means ssh cannot ask for a key passphrase
or accept a new host key, so load your key with `ssh-add` and connect once with plain
`ssh` first. A custom ssh command (`GIT_SSH_COMMAND` / `core.sshCommand` / `GIT_SSH`)
must accept OpenSSH `-o` options, since clwt appends its own after it.

```bash
claude/scripts/clwt install     # symlinks clwt + its completion; run once
```

That links `~/.local/bin/clwt` and, for Tab completion,
`~/.local/share/bash-completion/completions/clwt`. Both are symlinks into the
repo, so edits take effect with no reinstall, and bash-completion autoloads the
second by name — no `.bashrc` change needed.

**zsh** has no equivalent autoload, so add two lines to `~/.zshrc` after your
existing `compinit`:

```zsh
autoload -Uz bashcompinit && bashcompinit
source ~/.local/share/bash-completion/completions/clwt
```

The completion runs unmodified there: `bashcompinit` invokes it through a
`compgen` shim that runs `emulate -L sh`, which turns on `KSH_ARRAYS` and gives
`${COMP_WORDS[COMP_CWORD]}` the 0-based indexing it expects. Calling the
function outside that emulation returns nothing — a testing artifact, not a
defect.

## Commands

| Command | |
|---------|--|
| `clwt` / `clwt list` | list this repo's managed worktrees, flagging unmanaged ones |
| `clwt new <type>/<slug>` | branch from the **current** origin default, create the worktree, launch |
| `clwt branch <branch>` | check out an existing local or origin branch, launch |
| `clwt open <branch>` | launch in an existing managed worktree |
| `clwt pr <number> [--force] [--no-review]` | check a pull request out into a worktree, launch (warns on forks) |
| `clwt root` | launch in the primary checkout |
| `clwt remove <branch> [--delete-branch]` | remove a clean managed worktree |
| `clwt prune [--yes]` | sweep worktrees whose branch has a merged PR — dry run without `--yes` |
| `clwt install` | symlink onto `PATH` (+ completion) |
| `clwt help` | usage |

`remove <branch> --delete-branch` deletes the branch with `git branch -d` when git sees it as merged (no `gh` needed). Otherwise, if GitHub reports a MERGED pull request for the branch whose head commit equals the local branch tip (a squash merge), it deletes with `git branch -D` and names the PR; this needs an authenticated `gh`. Any other case refuses and removes nothing; drop `--delete-branch` to remove only the worktree. If the branch gains a commit while the check runs, the worktree is still removed but the branch is kept. A pull request merged into a non-default base branch also counts as merged. `clwt` looks pull requests up with `--repo owner/repo`, so it asks github.com, or the host in `GH_HOST`, not the origin host; same-named pull requests from forks are never accepted.

Worktrees live at `~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`.
`clwt` refuses to create, move, or remove anything outside that root — worktrees made
by other means show up in `list` marked `(unmanaged)`.

`--yolo` on any launching subcommand adds `--dangerously-skip-permissions`, which
**bypasses every permission check for that session**. Arguments after `--` pass
through to `claude` untouched:

```bash
clwt new feat/token-refresh --yolo -- --model opus
```

A leftover local branch from a merged/force-pushed PR resets automatically when `clwt pr`
can prove it holds no commits of its own; otherwise the branch is left untouched, and a
checkout failure names `--force` to reset it explicitly (see `clwt help` for the exact
wording).

When that PR branch already has a managed worktree, `clwt pr` refreshes it only after
verifying the canonical PR URL, the exact GitHub head commit, a clean working tree, and the
last head that `clwt` verified. Safe fast-forwards happen normally; rewritten history resets
only from that recorded head. `--force` does not bypass these checks. Ignored local files such
as `.env` are preserved, and the refresh is refused if the new PR tree would overwrite one.
An older markerless PR worktree can migrate only when its native Git tracking matches the PR
and the update is a fast-forward; rewritten history is refused because no last-verified head
exists yet.

Every launching subcommand also passes `--name` to `claude`, naming the session after the PR
number (`PR-<n>`), the branch, or the primary checkout's current branch for `root` — branch
names with slashes as dashes, and no name on a detached HEAD. A developer's own `--name`/`-n` after `--` overrides it,
since `claude` takes the last value it sees.

`clwt pr <n>` always fetches the PR's context into `pr-context.md`, in a session folder
alongside the worktree; unless `--no-review`, it also sends a one-line
`/pr-review <n> <path>` startup prompt, so the session opens already reviewing.
`--no-review` skips the prompt but still writes the file (a fetch failure then only warns
instead of refusing to launch). Unless `--no-review`, `clwt pr` first fetches the PR's base
branch from origin; if that fetch fails, it withholds the prompt and warns. When the review
is withheld for any reason and stdin and stderr are both terminals, `clwt pr` waits for Enter
before launching (Ctrl-D continues, Ctrl-C cancels). `clwt remove`/`clwt prune` delete the
session folder with the worktree. Details, including the residual AGENTS.md/CLAUDE.md risk, are in the
[`clwt` skill](../claude/skills/clwt/SKILL.md) and [ADR 0014](decisions/0014-pr-context-handoff.md).

## Why it's a CLI and not a skill

`claude` has no "start in directory" flag — it inherits its working directory from
whatever launched it. So `clwt` works by `cd`-ing into the worktree and `exec`-ing
`claude` there, which only a shell outside Claude can do: **Claude cannot relaunch
itself into a new directory.** For `new`, `branch`, `open`, `pr`, and `root`, Claude's
job is to recommend the command; you run it. `list`, `remove`, and `prune` don't
launch anything, so Claude can run those.

Because the session starts already rooted in the right worktree, `git -C` is never
needed — the settings *template* carries a `Bash(git -C *)` deny, which the installer
flags do-not-migrate (a global deny can't be re-allowed per project); the `clwt` skill
treats avoiding `git -C` as a convention.

## Untracked files and the issue database

New worktrees receive the untracked files matching `.worktreeinclude` (your `.env`
and friends), copied from the primary checkout so the project can actually run.

**`.beads/` is never copied**, even if `.worktreeinclude` matches it. Worktrees share
the primary checkout's single issue database through the git common dir; copying it
forks them and loses writes ([PR #48](https://github.com/itsacoyote/ai-config/pull/48)).

Every launched session gets `CLWT_REPO_ROOT` pointing at the primary checkout, so any
tracker can find that one central database — `bd` resolves it on its own, but a future
tracker won't have to reimplement git internals to do the same.

## Tests

No CI and no package manager here, so the suite is manual:

```bash
bash claude/scripts/tests/clwt-test.sh
```

It builds a throwaway world under a fake `$HOME` — a bare remote, a clone, and stub
`claude`/`gh` binaries that log how they were invoked — then asserts against it.
Exits non-zero on any failure.

