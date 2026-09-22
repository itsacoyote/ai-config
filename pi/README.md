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
only for `pwt pr` and `pwt prune`. The repository must have an `origin` remote.

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
| `pwt pr <number> [--force]` | Check out a pull request and launch Pi with restricted model tools. |
| `pwt root` | Launch Pi in the primary checkout. |
| `pwt remove <branch> [--delete-branch]` | Remove a clean managed worktree. |
| `pwt prune [--yes]` | Find worktrees with merged pull requests; `--yes` applies the dry run. |
| `pwt install` | Symlink the CLI and completion into the user paths above. |
| `pwt help` | Show command help. |

Running `pwt` without a command is the same as `pwt list`.

### Launch and repository behavior

Launching commands physically enter the selected checkout with `cd -P`, then execute the
`pi` binary resolved before that directory change. Pi and its child processes therefore
start in the correct physical working directory.

Arguments after `--` pass to Pi unchanged for normal launches. Pi has no native
permission-bypass mode, so `pwt` does not provide `--yolo` or translate it into another
flag.

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
forwarded arguments, `pwt` appends this policy as the final Pi arguments:

```text
--no-extensions --tools read,grep,find,ls --no-approve
```

The validator rejects Pi commands and options that could change tools or trust, load an
extension, disable context files, or resume a session rooted elsewhere. `--no-approve`
also prevents Pi from loading project settings, resources, packages, and skills;
repository context files remain enabled intentionally.

This is a model-tool restriction, not an OS sandbox. Git checkout may run locally
configured hooks or filters, allowed read tools can expose copied secrets to the model
provider, and Pi still uses trusted global configuration. Review the pull request's source
and local Git configuration before launching it.

### Tests

Run the self-contained suite manually:

```bash
bash pi/scripts/tests/pwt-test.sh
```

It builds a disposable Git world with fake `HOME`, `pi`, and `gh` fixtures. The runtime,
completion, and suite target stock macOS Bash 3.2. The independent-port rationale and
Pi-specific trust boundary are recorded in
[ADR 0012](../docs/decisions/0012-pwt-worktree-cli.md).
