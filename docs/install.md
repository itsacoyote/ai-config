# Installing the library

The library is consumed **globally** — one set of links serves every project on the
machine, for all three harnesses. There is no per-project copy, and no reinstall step:
after the first run, `git pull` on `main` is the update
([ADR 0013](decisions/0013-link-config-library.md)).

```sh
bash link.sh --dry-run   # print the full plan, including every deletion; write nothing
bash link.sh             # link, clean, and install the worktree CLIs
```

| Flag | Effect |
|---|---|
| `-n`, `--dry-run` | Print the plan and exit. A fatal entry exits 2 in both modes. |
| `-h`, `--help` | Usage. |

**Run it yourself, not through an agent** — the harness homes are human-owned (on this
maintainer's machines a settings-level deny enforces it), and **run it from the primary
checkout on `main`**: the links point into the checkout it runs from, so a linked worktree is
refused and a feature branch would put unmerged files into live sessions. What it does:

- **Links** every top-level entry of `claude/{skills,agents,rules,references,scripts,hooks}`
  into `~/.claude/<dir>/`, `claude/CLAUDE.md` and `claude/statusline-command.sh` into
  `~/.claude`, `agents/skills/*` into `~/.agents/skills/`, `agents/AGENTS.md` as
  `~/.codex/AGENTS.md`, `codex/rules/ai-config.rules` into `~/.codex/rules/`, and
  `pi/AGENTS.md` as `~/.pi/agent/AGENTS.md`. The same layout under a **private directory**
  (below) is linked alongside; a name present in both is an error, not an override.
- **Cleans** the managed directories: inside the six `~/.claude` content dirs,
  `~/.agents/skills`, and `~/.codex/rules`, everything it did not link is deleted, except
  `~/.claude/skills/synced`, `~/.codex/rules/default.rules`, and `.DS_Store`. Every deletion
  is in the dry-run plan. It never enumerates anything else, refuses a managed directory that
  is itself a symlink, and never deletes a hook that either settings file registers unless a
  source root re-creates it.
- **Installs the worktree CLIs** by running `clwt install`, `cwt install`, and `pwt install`,
  so `~/.local/bin` and the completions point into this checkout.
- **Never touches** `~/.claude/settings.json`, `settings.local.json`, `~/.codex/config.toml`,
  `~/.pi/agent/settings.json`, or any auth file. A single file already at a link's place is
  replaced only when byte-identical; otherwise the run stops before writing anything.
  Inside the managed directories this does not apply: a real file there is an extra and is
  deleted, then re-linked if a source root provides the name. Every such deletion is in the
  dry-run plan.

A second run prints `no changes`. Recovery from a moved checkout, a drifted home, or a fresh
machine is the same command.

## The private directory

Work-only content lives outside the repo in `~/.ai-private`, with the same layout as the
harness trees plus two files:

```text
~/.ai-private/
├── claude/{skills,agents,rules,references,scripts,hooks}/   # linked like the repo's
├── agents/skills/                                            # linked like the repo's
├── work-rules.md              # instructions that must load only inside work checkouts
└── links.txt                  # extra pairs, one `source<TAB>target` per line, `~/` allowed
```

`links.txt` is how `work-rules.md` reaches the parent directories of work checkouts and of
their centralized worktrees, where Claude Code's parent-directory `CLAUDE.md` walk picks it
up (Codex and Pi follow the same file through the work-scope line in their user files):

```text
~/.ai-private/work-rules.md	~/code/work-org/CLAUDE.md
~/.ai-private/work-rules.md	~/code/.worktrees/work-org/CLAUDE.md
```

Keep the parent file named `CLAUDE.md`, not `AGENTS.md`: Claude Code reads a parent
`AGENTS.md` only when no `CLAUDE.md` exists anywhere from the working directory upward, and
work repos carry their own. Targets must be under `$HOME`; every line is validated before
anything is written.

## Hooks and settings, by hand

`claude/settings.json` is the template: register the hook lines it lists (`bash-guard.sh` on
`PreToolUse`, `beads-gate.sh` and `session-orient.sh` on `SessionStart`) plus any private
hooks in your own `~/.claude/settings.json`. `notify.sh` and `skill-check.sh` ship unregistered.
Hook paths do not change when the files become links, so existing registrations keep working.
The hooks need `jq` on the PATH that hooks run with; `bash-guard.sh` denies every Bash call
until it is there rather than silently letting commands through.

| Hook | Event | What it does |
|---|---|---|
| `bash-guard.sh` | PreToolUse (Bash) | Denies `gh` subcommands that touch secrets, auth, or keys, and shell reads of credential files; fails closed without `jq` |
| `beads-gate.sh` | SessionStart | Reminds the session that beads is the system of record |
| `session-orient.sh` | SessionStart | Prints worktree, branch, and clean/dirty state via `worktree-status.sh` |
| `notify.sh` | Notification (optional) | macOS banner and sound when Claude waits on you |
| `skill-check.sh` | PreToolUse (optional) | Reminds the session to invoke `git-commit` before committing and `create-pr` before opening a PR |

Two helper scripts in `claude/scripts/` are allow-listed in the template so agents can run them
without a prompt: `worktree-status.sh` (orientation for the current directory, `--brief` for one
line) and `wt-status.sh <dir>` (branch, head, status, and rebase state of another registered
worktree of the current repository; it refuses any other directory and runs git with
config-driven command execution disabled). Both have suites under `claude/scripts/tests/`.

## Before the first run

Take an archive of the managed directories and the four single files (`~/.claude/CLAUDE.md`,
`~/.claude/statusline-command.sh`, `~/.codex/AGENTS.md`, `~/.pi/agent/AGENTS.md`) outside
the private directory; that archive is the rollback. Move the four single files aside if they
differ from the templates, then `bash link.sh --dry-run` and read every `delete` line.

Two Claude Code notes: this repo has no `CLAUDE.md`; Claude Code 2.1.277 or later reads its
`AGENTS.md` directly and prints an `AGENTS.md loaded` line at session start (the file does not
appear in `/memory` or `/context`). And a session in a worktree under `.claude/worktrees/` also
loads the primary checkout's `AGENTS.md` from the parent path.

## MCP servers

`.mcp.json` configures two optional servers:

| Server | Purpose |
|--------|---------|
| `playwright` | Browser automation for `qa-review` evidence capture and e2e |
| `github` | GitHub API for interactive use (needs `GITHUB_PERSONAL_ACCESS_TOKEN`) |

Both are optional — skills degrade gracefully when a server isn't present (e.g. `qa-review` skips evidence capture). Git/GitHub operations prefer the `gh` CLI regardless (`github-tool-preference` rule).
