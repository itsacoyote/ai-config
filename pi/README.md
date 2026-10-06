# Pi configuration

Pi-specific configuration and developer tooling live here. Portable Open Agent Skills
shared with Codex live separately under [`../agents/skills`](../agents/skills/).

## What's here

| File | What it is |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Personal global Pi context, linked as `~/.pi/agent/AGENTS.md` by the repo's `link.sh` |
| [`scripts/pwt`](scripts/pwt) | Developer-run worktree CLI that launches Pi |
| [`scripts/pwt-completion.bash`](scripts/pwt-completion.bash) | Bash and zsh completion for `pwt` |
| [`scripts/tests/pwt-test.sh`](scripts/tests/pwt-test.sh) | Self-contained `pwt` regression suite |

`pi/AGENTS.md` is a personal global file, not a project template. The human-run `link.sh`
at the repo root symlinks it into `~/.pi/agent/` (see the
[root README](../README.md#installing-the-library)); never copy it into a shared repository.
[ADR 0008](../docs/decisions/0008-pi-global-only-config.md) records that boundary and
[ADR 0013](../docs/decisions/0013-link-config-library.md) the link.

## `pwt` — worktree CLI

`pwt` manages Git worktrees and launches Pi inside the selected checkout. Run it from
your shell, not from inside an active Pi session: launching commands change directory
and replace the current process with a new Pi session.

**Prerequisites:** stock macOS Bash 3.2 or newer and Git. Authenticated `gh` is required
only for `pwt pr` and `pwt prune`. The repository must have an `origin` remote. The network
steps of `pwt new` and `pwt branch` over an SSH remote run ssh in batch mode with a connect
timeout, so an unreachable remote fails with git's own error instead of hanging; batch mode
also means ssh cannot ask for a key passphrase or accept a new host key, so load your key
with `ssh-add` and connect once with plain `ssh` first. A custom ssh command
(`GIT_SSH_COMMAND` / `core.sshCommand` / `GIT_SSH`) must accept OpenSSH `-o` options, since
pwt appends its own after it.

Install the command and Bash completion from this repository's root:

```bash
pi/scripts/pwt install
```

This creates symlinks at `~/.local/bin/pwt` and
`~/.local/share/bash-completion/completions/pwt`. Because they point into this checkout,
changes take effect without reinstalling. Bash-completion 2.x loads the completion by
filename.

For zsh, initialize the Bash-completion bridge after `compinit`, then source the installed
completion:

```zsh
autoload -Uz bashcompinit && bashcompinit
source ~/.local/share/bash-completion/completions/pwt
```

### Commands

| Command | Purpose |
|---|---|
| `pwt list` | List this repository's worktrees and mark unmanaged entries. |
| `pwt new <type>/<slug>` | Create a branch from the current origin default, create its worktree, and launch Pi. |
| `pwt branch <branch>` | Check out an existing local or origin branch and launch Pi. |
| `pwt open <branch>` | Launch Pi in an existing managed worktree. |
| `pwt pr <number> [--force] [--no-review]` | Check out a pull request and launch Pi with restricted model tools. |
| `pwt root` | Launch Pi in the primary checkout. |
| `pwt remove <branch> [--delete-branch]` | Remove a clean managed worktree. |
| `pwt prune [--yes]` | Find worktrees with merged pull requests; `--yes` applies the dry run. |
| `pwt install` | Symlink the CLI and completion into the user paths above. |
| `pwt help` | Show command help. |

Running `pwt` without a command is the same as `pwt list`.

`remove <branch> --delete-branch` deletes the branch with `git branch -d` when git sees it as merged (no `gh` needed). Otherwise, if GitHub reports a MERGED pull request for the branch whose head commit equals the local branch tip (a squash merge), it deletes with `git branch -D` and names the PR; this needs an authenticated `gh`. Any other case refuses and removes nothing; drop `--delete-branch` to remove only the worktree. If the branch gains a commit while the check runs, the worktree is still removed but the branch is kept. A pull request merged into a non-default base branch also counts as merged. `pwt` asks the origin host. It accepts a merged fork pull request only for a branch `pwt pr` checked out (through its recorded PR URL). A newer open or closed pull request on a reused branch name hides an older merged one, so the branch is refused.

### Launch and repository behavior

Launching commands physically enter the selected checkout with `cd -P`, then execute the
`pi` binary resolved before that directory change. Pi and its child processes therefore
start in the correct physical working directory.

Arguments after `--` pass to Pi unchanged for normal launches. Pi has no native
permission-bypass mode, so `pwt` does not provide `--yolo` or translate it into another
flag.

Every launching subcommand also passes `--name` to Pi, naming the session: `pr <n>` becomes
`PR-<n>`; `new`/`branch`/`open` use the branch with slashes as dashes; `root` uses the primary
checkout's current branch, also with slashes as dashes, or no name on a detached HEAD. A developer's own override must use
the two-token form, `--name X` or `-n X` — Pi silently ignores `--name=X`. No name is added
when the first argument after `--` is a Pi command word (`auth`, `install`, `remove`,
`uninstall`, `update`, `list`, `config`), so that command still runs; `pwt pr`'s enforced
tool/trust suffix still comes last.

Every launched session receives `PWT_REPO_ROOT`, the absolute primary-checkout path.
`pwt` normally discovers that path from Git. A supplied `PWT_REPO_ROOT` must name a valid
primary checkout and, when invoked inside Git, the current repository. This override exists
for controlled use and the self-contained test suite.

Worktrees live at
`~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`. `pwt`, `cwt`, and
`clwt` intentionally share that managed root, so all three list the same repository
worktrees even though each launches only its own harness.

New worktrees copy untracked files matched by the primary checkout's
`.worktreeinclude`, such as a local `.env`. `.beads/` is always excluded because every
worktree must use the one issue database reached through Git's common directory. Removal
refuses dirty or out-of-root targets. Prune selects only clean worktrees with a verified
merged pull request and remains a dry run unless `--yes` is present.

### Pull-request restrictions

Use `pwt pr` only for trusted pull requests under the local-user threat model. The model
gets context files but only the `read`, `grep`, `find`, and `ls` tools. After validating
forwarded arguments, `pwt` appends this policy as the final Pi options (in review mode,
only the startup prompt follows it); in review mode (not `--no-review`) the skill pin
comes first, so the full enforced tail is:

```text
--no-skills --skill <personal pr-review skill path> --no-extensions --tools read,grep,find,ls --no-approve
```

The validator rejects Pi commands and options that could change tools or trust, load an
extension, disable context files, or resume a session rooted elsewhere. `--no-approve`
also prevents Pi from loading project settings, resources, packages, and skills;
repository context files remain enabled intentionally.

This is a model-tool restriction, not an OS sandbox. Git checkout may run locally
configured hooks or filters, allowed read tools can expose copied secrets to the model
provider, and Pi still uses trusted global configuration. Review the pull request's source
and local Git configuration before launching it.

### Review startup and `pr-context.md`

`pwt pr <n>` always fetches the PR's context into `pr-context.md`, in a session folder
alongside the worktree; unless `--no-review`, it also sends a one-line
`/skill:pr-review <n> <path>` startup prompt as the final argument, so the session opens
already reviewing. `--no-review` skips the skill pin and the prompt but still writes the
file; a context-fetch failure then only warns instead of refusing to launch. Because Pi keeps the
first-discovered skill on a name collision, review mode also pins skill discovery to the
personal `~/.agents/skills/pr-review` with `--no-skills --skill <path>` (above), so a PR
shipping its own `.agents/skills/pr-review` cannot replace the review; if that personal
skill is missing, `pwt pr` exits non-zero naming `--no-review`, and a passthrough
`--skill`/`--no-skills`/`-ns`/`--prompt-template` is refused in review mode for the same reason.
`pwt remove`/`pwt prune` delete the session folder with the worktree, including Pi's own
conversation history for it. Even with the skill pinned, a PR can still change a root
`AGENTS.md` that the launched session loads; the fork warning is the only signal of that,
so treat a fork PR's own `pr <n>` launch with the same caution as running any of its code.

### Tests

Run the self-contained suite manually:

```bash
bash pi/scripts/tests/pwt-test.sh
```

It builds a disposable Git world with fake `HOME`, `pi`, and `gh` fixtures. The runtime,
completion, and suite target stock macOS Bash 3.2. The independent-port rationale and
Pi-specific trust boundary are recorded in
[ADR 0012](../docs/decisions/0012-pwt-worktree-cli.md).
