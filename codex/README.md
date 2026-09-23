# Codex CLI configuration

Codex-specific conventions for [Codex CLI](https://developers.openai.com/codex/) sessions.
Portable Open Agent Skills shared with Pi live separately under [`../agents/skills`](../agents/skills/).

## What's here

| File | What it is |
|---|---|
| `AGENTS.md` | Always-on engineering conventions, loaded from a project's root |
| `../agents/skills/` | Portable skills for commits, branches, PRs, and skill authoring |
| rules/ai-config.rules | Codex command approval rules managed by this repository |

The skills use Codex's native Agent Skills layout — Codex invokes them implicitly when the
task matches a skill's description, or explicitly via `$git-commit`, `$branch-names`,
`$create-pr`, `$writing-skills`.

## Install into a project

Install portable skills from this repo's root:

```sh
mkdir -p <target>/.agents/skills
cp -R agents/skills/. <target>/.agents/skills/
```

Rules:

- `codex/AGENTS.md` is optional project guidance. Merge relevant sections into the target's
  existing `AGENTS.md` by hand; never overwrite project or personal instructions.
- Portable skills stay under `.agents/skills/` — never flatten them into the project root.
- If the target already has `.agents/skills/<name>/` directories, merge or rename per
  skill rather than overwriting.

## Or link the skills once, personally

Codex also discovers skills in `~/.agents/skills` across every project. The repo's human-run
`link.sh` (see the [root README](../README.md#installing-the-library)) symlinks every shared
skill there, links `agents/AGENTS.md` as `~/.codex/AGENTS.md`, and links the command rules
below into `~/.codex/rules/`. It never touches `~/.codex/config.toml` or auth files.

## Command approval rules

Codex uses .rules files for command-specific approval decisions. This repository carries
an additive rules file, `codex/rules/ai-config.rules`, containing the approved workflow
commands translated from the Claude allowlist. `link.sh` symlinks it into
`~/.codex/rules/`, next to Codex's own `default.rules`, which is left alone. Restart Codex
after linking. The rules feature is experimental in Codex; inspect a rule with:

~~~bash
codex execpolicy check --pretty \
  --rules ~/.codex/rules/ai-config.rules -- git add path/to/file
~~~

These rules allow commands without prompting; they do not disable Codex's sandbox.

## `cwt` — worktree CLI

`codex/scripts/cwt` is the Codex-specific worktree CLI. Run it from your shell, not from
inside an active Codex session: its launching commands change directory and replace the
current process with a new Codex session.

**Prerequisites:** stock macOS Bash 3.2 or newer and Git. Authenticated `gh` is required
only for `cwt pr` and `cwt prune`. The repository must have an `origin` remote. The network
steps of `cwt new` and `cwt branch` over an SSH remote run ssh in batch mode with a connect
timeout, so an unreachable remote fails with git's own error instead of hanging; batch mode
also means ssh cannot ask for a key passphrase or accept a new host key, so load your key
with `ssh-add` and connect once with plain `ssh` first. A custom ssh command
(`GIT_SSH_COMMAND` / `core.sshCommand` / `GIT_SSH`) must accept OpenSSH `-o` options, since
cwt appends its own after it.

Install the command and Bash completion from this repository's root:

```bash
codex/scripts/cwt install
```

This creates symlinks at `~/.local/bin/cwt` and
`~/.local/share/bash-completion/completions/cwt`. Bash-completion 2.x autoloads the
completion by filename. zsh users must initialize its Bash-completion bridge and source
the installed file manually after `compinit`:

```zsh
autoload -Uz bashcompinit && bashcompinit
source ~/.local/share/bash-completion/completions/cwt
```

### Commands

| Command | Purpose |
|---|---|
| `cwt list` | List this repository's worktrees and mark unmanaged entries. |
| `cwt new <type>/<slug>` | Create a branch from the current origin default, create its worktree, and launch Codex. |
| `cwt branch <branch>` | Check out an existing local or origin branch and launch Codex. |
| `cwt open <branch>` | Launch Codex in an existing managed worktree. |
| `cwt pr <number> [--force]` | Check out a pull request, warn for forks, and launch Codex. |
| `cwt root` | Launch Codex in the primary checkout. |
| `cwt remove <branch> [--delete-branch]` | Remove a clean managed worktree. |
| `cwt prune [--yes]` | Find worktrees with merged pull requests; `--yes` applies the dry run. |
| `cwt install` | Symlink the CLI and completion into the user paths above. |
| `cwt help` | Show command help. |

Worktrees live at
`~/github/.worktrees/<owner>/<repo>/<branch-with-slashes-as-dashes>/`. `cwt` and `clwt`
intentionally share that managed root, so either tool sees the same repository worktrees;
each still launches only its own harness.

Launching commands physically `cd` into the selected checkout and `exec codex`. They do
not rely on Codex's native `-C` option, so startup hooks and child processes inherit the
same real working directory. Each launched session receives `CWT_REPO_ROOT` pointing at
the primary checkout.

`--yolo` passes Codex's native `--yolo` flag, which bypasses approvals and sandboxing for
that session. Arguments after `--` pass through to Codex unchanged. On `cwt pr`, `--force`
allows `gh pr checkout` to reset a leftover local branch; without it, automatic reset is
allowed only when the branch is proven to contain no local-only commits.

When that PR branch already has a managed worktree, `cwt pr` refreshes it only after
verifying the canonical PR URL, the exact GitHub head commit, a clean working tree, and the
last head that `cwt` verified. Safe fast-forwards happen normally; rewritten history resets
only from that recorded head. `--force` does not bypass these reuse checks. Ignored local
files such as `.env` are preserved, and the refresh is refused if the new PR tree would
overwrite one. These tool-neutral markers are shared with `clwt`, so either launcher can
safely resume a PR worktree created by the other.
An older markerless PR worktree can migrate only when its native Git tracking matches the PR
and the update is a fast-forward; rewritten history is refused because no last-verified head
exists yet.

### Untracked files and beads

New worktrees copy ignored or untracked files matched by the primary checkout's
`.worktreeinclude`, such as a local `.env`. The `.beads/` directory is always excluded:
worktrees share the primary checkout's single issue database through Git's common
directory, and copying it would fork that state.

### Tests

Run the self-contained suite manually:

```bash
bash codex/scripts/tests/cwt-test.sh
```

It builds a disposable Git world with fake `HOME`, `codex`, and `gh` fixtures. The CLI,
completion, and suite target stock macOS Bash 3.2.
