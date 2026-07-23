---
name: document
description: Use when an implemented and validated change needs its final documentation audit, documentation commit, and draft pull-request material prepared for explicit human handoff.
metadata:
  category: workflow
---

# Document

The final pre-PR step. Make the change understandable and operable from the repository's documentation, commit the documentation coherently, and prepare—but do not silently publish or change—the pull request.

## When NOT to use

Do not run before Validate approves. A change with genuinely no affected documentation still needs the audit, but should record “no documentation changes required” rather than manufacture churn.

**Preflight (required).** Before doing any workflow work, resolve
`../../scripts/beads-preflight.sh` relative to this skill's directory and execute the resolved
absolute path. If it exits non-zero, **stop** and tell the user to run `setup-beads`, then retry.

## Audit the diff

Resolve `../../scripts/diff-scope.sh` from this loaded skill directory and run its absolute path with `--range`. Use that base-to-HEAD range to inspect committed work, then run `git status --porcelain` to include unstaged and untracked durable artifacts. Never derive script paths from the repository working directory.

Read the approved spec and validation summary from the feature epic. Treat untracked ADRs, generated reference docs, and other durable artifacts as in scope even though the committed diff cannot see them.

## Documentation surfaces

Compare the change against every applicable surface; update only what the change made incomplete or wrong:

- README setup, commands, prerequisites, environment variables, configuration, migrations, and testing;
- the target project's `AGENTS.md` and any still-authoritative client guidance when conventions, directories, tools, or architecture changed;
- user/developer feature docs, examples, limitations, and migration notes;
- API endpoints, request/response contracts, authentication, errors, and rate limits;
- inline rationale for non-obvious rules and workarounds—document why, not obvious mechanics;
- changelog entries when the project maintains one;
- ADRs for significant decisions, following `documentation-and-adrs`.

A new developer should be able to clone, configure, understand, and verify the changed behavior from these docs. Do not copy implementation details into multiple sources of truth.

## Verify and commit documentation

Run [`project-checks`](../project-checks/SKILL.md). Follow [`git-commit`](../git-commit/SKILL.md), stage explicit documentation paths, and include any durable untracked artifact created earlier in the workflow. Never modify signing configuration, signing keys, or signature policy.

If the repository requires signed commits and the automated client cannot sign, an unsigned documentation commit may be created only when project guidance allows it; then **stop and ask the user to sign** it. Surface the exact commit message and do not proceed to remote operations.

Pushing unsigned commits is forbidden whenever repository policy requires signatures. Before any proposed push, determine the branch base and check signatures exactly as project policy requires. For repositories using the standard policy, run:

```bash
git log --format='%G?' <base>..HEAD | grep -c '^N'
```

The unsigned count is only an early check. Verify every commit in `<base>..HEAD` with `git verify-commit <sha>` and inspect `%G?` under the repository's trust policy. The standard policy accepts only `G`; `U` is accepted only when project guidance explicitly allows a cryptographically valid but untrusted key. Reject `N` (unsigned), `B` (bad), `E` (cannot check), `X`/`Y` (expired), `R` (revoked), and every unknown status. If any required commit fails, **never push unsigned** or invalidly signed commits: stop and ask the user to sign or repair each one. A rebase or amend invalidates signatures and requires the complete check again. Document never disables signature verification or uses a force-push workaround.

This skill does not push automatically. Present the exact push command only after checks and signing policy pass; the human owns signing and pushing when project guidance says so.

## Prepare draft PR material

Follow [`create-pr`](../create-pr/SKILL.md) to run its preflight and prepare a Conventional Commit title plus the repository's PR-template body. Include:

- what changed and why, grouped by responsibility rather than a raw file list;
- how it was tested and independently validated;
- migrations, compatibility notes, screenshots/evidence, and linked issues/ADRs where applicable.

Do not include AI attribution.

Treat all remote PR state as human-gated:

- New PRs are always a **draft PR**.
- Ask for **explicit approval** before creating a draft PR or editing an existing PR's title/body.
- Never mark a PR ready, never approve, never request changes, and never merge.
- Never close, relabel, retarget, or otherwise change PR state silently.
- If commits are not signed and pushed under project policy, stop before any PR create/update command.

Prepare the title, body, and exact proposed command in-session, then wait. An existing PR is reported, not edited, until the user approves the specific update.

## Completion and human gate

Confirm `git status --porcelain` contains no orphaned durable file. Record the documentation audit and any deliberately deferred docs on the epic; create follow-up issues for real deferrals.

The terminal result is: documentation committed, required signatures verified or handed to the user, push/PR commands prepared, and the branch waiting at the PR human gate. Only after the user explicitly approves and remote prerequisites are satisfied may the parent create or update the draft and close the feature epic.

Document and `autorun` never mark a PR ready, never approve it, and never merge it. Those remain human actions.
