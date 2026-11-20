# pr-watch.json: baseline schema and rules

The baseline is what the coordinator last saw for each watched PR. Each run compares live GitHub state to it. `pr-watch.json` lives next to `config.json` and `board.json` in the coordinator state directory.

## Schema

```json
{
  "checked_at": "2026-01-01T12:00:00Z",
  "prs": {
    "123": {
      "ticket": "TICKET-1",
      "branch": "feat/example-slug",
      "state": "OPEN",
      "isDraft": true,
      "baseRefName": "main",
      "headRefOid": "0000000000000000000000000000000000000000",
      "reviewDecision": "",
      "closed_at": "",
      "seen_review_ids": [],
      "seen_comment_ids": [],
      "unblocks": "Start TICKET-2; its session rebases onto main after this merges.",
      "notes_sent": []
    }
  }
}
```

| Field | Meaning |
|---|---|
| `branch` | The session's stable key. A `ListAgents` row named after the branch (slashes as dashes) or named `PR-<n>` for this PR is that session |
| `state`, `isDraft`, `baseRefName`, `headRefOid`, `reviewDecision` | Copied from `gh pr view` |
| `closed_at` | Merge or close time, set when `state` leaves `OPEN`; drives board cleanup |
| `seen_review_ids`, `seen_comment_ids` | Every review and comment id already handled, bot ids included |
| `unblocks` | Free-text rule (see below) |
| `notes_sent` | Notes already sent (see below) |

## What is watched

- The developer's new PRs are added automatically.
- Another person's PR is added only when it blocks the developer's work. Say so in the reply when adding one.

## What counts as new

One definition; other files link here.

A PR has news when any of these is true since the baseline:

1. A review or comment id is not in `seen_*_ids`, its author is not a bot, and its author is not the developer (login from `config.json`).
2. `reviewDecision` changed. An empty string is not approval.
3. The PR merged.
4. The PR closed without merging, or its `baseRefName` changed. When the PR is a stacked child and its parent merged in the same window, report it as "parent #<n> merged; this PR was retargeted to <base>" (or "…was closed by GitHub"), not as a plain close, and check the new base before any note.

### Bot detection

`gh pr view --json comments,reviews` returns only `author.login`. It has no `[bot]` suffix and no bot flag.

1. Look up authors only when new ids appear.
2. Classify them with `gh api repos/{owner}/{repo}/issues/<n>/comments` and `gh api repos/{owner}/{repo}/pulls/<n>/reviews`. An author with `user.type == "Bot"` is a bot.
3. Add each bot login to `config.json`. A known bot login needs no further lookup.

## Read commands

| Need | Command |
|---|---|
| PR state | `gh pr view <n> --json state,isDraft,baseRefName,headRefOid,reviewDecision,reviews,comments,files,mergedAt,author` |
| CI | `gh pr checks <n>`. Read the output, not the exit code: non-zero means pending or failing |
| Signatures | `gh api repos/{owner}/{repo}/pulls/<n>/commits`, then `commit.verification.verified` on each commit |

GitHub is authoritative for pushed commits. Use the PR's real base for stacked PRs. Every `gh api` call (signatures, bot detection) prompts for approval; this is expected.

## notes_sent

Each entry: `{key, headRefOid, sent_at, status}`.

- `key` is the triggering review id or comment id, one of `decision:<value>`, `merged`, `closed`, or `unblocks:<target>` for each action taken from an `unblocks` entry (`<target>` is the branch told to rebase, or the ticket handed to the developer).
- `status` is `sent, not confirmed`, `held`, or `refused`.

Rules:

1. Before any send, skip it when `notes_sent` already has that key for that PR.
2. Write the entry right after each send, before the board write.
3. That mid-turn write changes only `notes_sent`. It keeps the previous seen ids and `state`. If the turn crashes before the board write, the next run replays the event to the board and does not send the note again.

## unblocks

Free text naming what can start and which session must rebase (example in the schema above).

- Keep the rule text. Never overwrite it.
- Record what was acted on as a `notes_sent` entry.
- What a merge with an `unblocks` entry must produce is in `SKILL.md` (Main loop).

## Turn write order

1. `notes_sent`, once per send.
2. Local `board.json`.
3. The board artifact (see [board.md](board.md)).
4. The full baseline, last.

If the artifact write fails (3-attempt cap, or the Artifact tool is unavailable), steps 2 and 4 still happen. The reply says the published board is stale.
