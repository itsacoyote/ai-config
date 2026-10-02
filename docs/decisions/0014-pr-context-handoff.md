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
- A failed fetch stops the launch, so a review never starts on partial data. Under
  `--no-review` it only warns and launches with no file, so the flag stays a working
  escape route.
- `remove` and `prune` delete the worktree's session folder, including Pi's session history
  for that worktree.
- The review skills read the file for intake. The Claude skill keeps its `gh` fallback. A
  new portable `agents/skills/pr-review` serves Codex and Pi; in Pi the file is the only
  intake path, and posting becomes a printed command the developer runs.
- `pwt pr`'s tool/trust boundary is unchanged.
- A pull request could otherwise replace the review by shipping its own
  `.agents/skills/pr-review` (Codex does not rank a personal skill above a project one on a
  name collision; Pi keeps the first-discovered skill). `cwt pr` withholds the startup
  prompt — warning, not refusing to launch — when a local `git diff` of the checked-out PR
  against its merge base touches a path under `.agents` or `.codex`, failing closed on a
  symlinked entry or a non-ASCII top-level name it cannot safely fold, and also when that
  tree is unchanged from the PR's own merge base but has since diverged from the base
  branch's current tip. `pwt pr` instead pins
  Pi's skill discovery to the personal `~/.agents/skills/pr-review` with `--no-skills
  --skill <path>`, ahead of its existing tool/trust suffix, and refuses a passthrough
  `--skill`/`--no-skills` in review mode. Claude ranks subagents the OPPOSITE way from
  skills — a project `.claude/agents/<name>.md` outranks a personal one of the same name —
  so a pull request shipping `.claude/agents/pr-security.md` (or `qa-review`,
  `senior-review`, `pr-context`, `pr-tests`, `design-review`) could replace that pass of the
  auto-started review the same way. `clwt pr` runs the matching guard, scoped to the
  top-level `.claude` directory instead of `.agents`/`.codex`.
- The portable skill's Codex and Pi paths differ at intake, QA, and posting. This fits
  ADR 0010's allowance for small capability differences: both paths are supported, and
  the method (intake → passes → severity table → curation gate → one review) is the same.

## Context file layout

The contract between the three writers and the two review skills. Writers emit exactly
this order; readers find sections by these exact headings.

```text
# Pull request #<n>

- URL: <canonical PR URL>
- Author: <login>
- Base: <base ref>
- Head: <head ref>
- Head commit: <40-hex head commit ID>
- Fork: <true|false>
- Fetched: <UTC time, ISO 8601>

## Description
## Linked issues
## Changed files
## CI checks
## Conversation comments
## Reviews
## Review comments
## Diff
```

- Header values are validated identifiers only. The title and every other free-text
  field live inside a section, never in the header.
- `Description` holds the `gh` JSON for title and body. The JSON sections (`Linked
  issues`, `Changed files`, `Conversation comments`, `Reviews`, `Review comments`) hold
  `gh` JSON output. `CI checks` holds `gh pr checks` text. `Diff` holds `gh pr diff`
  text.
- Each section body is one fenced block whose fence is longer than the longest backtick
  run in that content, or the single line `(none)`. A list `gh` capped ends with the
  line `(truncated at N)` after its fence.

## Consequences

- Reviews start without typing, and intake costs no model turns or `gh` approvals.
- Pi can review PRs without gaining a shell.
- The file is a snapshot taken at launch. Skills that can reach `gh` re-check the head
  commit before posting; Pi's printed command carries the snapshot's commit ID.
- Three scripts each carry their own fetch code (ADR 0006). The section layout is the
  contract between the CLIs and the skills; changing it means changing every producer and
  consumer.
- Removing a PR worktree now also deletes its Pi conversation history.
- The `.agents`/`.codex` guard, the `.claude` guard, and the skill pin stop a pull request
  from *replacing* the review skill or subagent, but not from changing a root `AGENTS.md`
  (or `CLAUDE.md` for Claude) that the harness loads into the auto-started session — that
  was already true when the review was typed by hand. The fork warning on the launch is the
  only signal of that; it is not a new risk this feature introduces.

## Alternatives considered

- **Give Pi bash in `pwt pr`.** Rejected: it removes the only protection a Pi PR session
  has against running untrusted code with the developer's credentials.
- **Store the PR data in a bead.** Rejected: Pi cannot run `bd` in a PR session, most
  reviewed repos have no beads database, and beads is being replaced.
- **Write the file inside the worktree.** Rejected: it would show in `git status`, and a
  PR could ship a same-named file.
- **Put the context directly in the prompt.** Rejected: large diffs exceed argv limits and
  flood the first message.
