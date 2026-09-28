# 14. Hand PR review context from the worktree CLIs to the session as a file

Date: 2026-09-28

Status: Accepted

Tracking: beads epic for branch `feat/query-start`

## Context

`clwt pr`, `cwt pr`, and `pwt pr` check a pull request out into a managed worktree and
launch a harness there. The review itself (`pr-review`) then starts with a fixed intake:
`gh pr view`, `gh pr view --comments`, `gh pr diff`. That intake needs no judgment, costs
turns and permission prompts, and is impossible in Pi: `pwt pr` limits the model to
`read,grep,find,ls` because Pi has no sandbox and the checkout is someone else's code.

Codex and Pi also have no `pr-review`. The Claude skill depends on Claude subagents, so it
cannot move into the shared `agents/skills/` library as-is (ADR 0010).

## Decision

- Each CLI's `pr` subcommand fetches the PR's data with `gh` before launch and writes it to
  `<git-common-dir>/<cli>/sessions/<worktree-name>/pr-context.md`, in a fixed section
  layout, on every run. The file lives in git's own directory, so it never shows in the
  worktree's status and the PR's content cannot place or replace it.
- `pr` sends the harness's `pr-review` invocation, including the file's path, as the
  startup prompt. `--no-review` suppresses it.
- A failed fetch stops the launch. A review never starts on partial data.
- `remove` and `prune` delete the worktree's session folder, including Pi's session history
  for that worktree.
- The review skills read the file for intake. The Claude skill keeps its `gh` fallback. A
  new portable `agents/skills/pr-review` serves Codex and Pi; in Pi the file is the only
  intake path, and posting becomes a printed command the developer runs.
- `pwt pr`'s tool/trust boundary is unchanged.

## Consequences

- Reviews start without typing, and intake costs no model turns or `gh` approvals.
- Pi can review PRs without gaining a shell.
- The file is a snapshot taken at launch. Skills that can reach `gh` re-check the head
  commit before posting; Pi's printed command carries the snapshot's commit ID.
- Three scripts each carry their own fetch code (ADR 0006). The section layout is the
  contract between the CLIs and the skills; changing it means changing every producer and
  consumer.
- Removing a PR worktree now also deletes its Pi conversation history.

## Alternatives considered

- **Give Pi bash in `pwt pr`.** Rejected: it removes the only protection a Pi PR session
  has against running untrusted code with the developer's credentials.
- **Store the PR data in a bead.** Rejected: Pi cannot run `bd` in a PR session, most
  reviewed repos have no beads database, and beads is being replaced.
- **Write the file inside the worktree.** Rejected: it would show in `git status`, and a
  PR could ship a same-named file.
- **Put the context directly in the prompt.** Rejected: large diffs exceed argv limits and
  flood the first message.
