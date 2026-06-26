---
name: document
description: Use as the final step before a PR goes to human review — audit and update every documentation surface affected by the change, write the PR description, and ready the PR.
disable-model-invocation: true
allowed-tools: Read Edit Write Bash(git *) Bash(gh *) Bash(find *) Bash(grep *)
---

# Document

The last step of the feature workflow, before human review. Make sure every change is fully reflected in the project's documentation. The bar: a junior engineer who has never seen this codebase could clone it, set it up, understand what changed and why, and run it — entirely from the docs. If they can't, something is missing.

Do not cut corners. "This seems obvious" and "this is a small change" are not reasons to skip documentation. If something changed, or now exists that didn't before, it gets documented.

## Start

Read the full diff — this is the source of truth for what changed:

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
git diff $(git merge-base HEAD ${BASE:-main}) HEAD
git status --porcelain          # also catch untracked/unstaged files the diff above misses
```

The diff shows only *committed* work; it cannot show a file that was created but never
committed. Run `git status --porcelain` too — durable artifacts authored earlier in the
workflow (most often an **ADR written during Define**, or generated docs) can sit untracked
and would otherwise slip past both this audit and the PR. Treat any untracked durable file as
in scope.

Then read the spec (if one exists) to understand intent.

## Documentation audit

Work every surface below. For each: read the current file, compare against the diff, then update. Don't guess.

- **README** — setup/getting-started, run commands, test commands, environment variables (name, purpose, example), configuration, database/migrations, new scripts, prerequisites. Remove or fix anything the change made wrong.
- **The project's `CLAUDE.md` / `AGENTS.md`** — new directories, new conventions or patterns this change establishes, new tools/scripts/commands, architectural shifts, new domain terms, changes to how tests run. Create it if missing. *(This is the **target project's** agent file, not this skills repo's.)*
- **Feature documentation** — anything a user or developer interacts with: what it does and why, how to use it (examples), required setup, limitations, how it relates to other features. Put it where the project's docs live.
- **API documentation** — for added/changed/removed endpoints: path + method, request params/headers/body (types, required/optional), response shapes and status codes, auth requirements, rate limits.
- **Inline documentation** — for complex logic, non-obvious business rules, and workarounds (document what, why, and what breaks if removed) and for public interfaces whose contract isn't clear from types. Comment the *why*, never the *what*.
- **Changelog** — if the project keeps one (or is public-facing): feature name + one-line description, breaking changes, migration steps.
- **ADRs** — if this feature involved a significant architectural decision, record it (see `documentation-and-adrs`).

## PR description

Write the PR body following the `create-pr` skill (what/why, no AI attribution). Include: what changed (the key files and their responsibilities), how it was tested/validated, and links to anything relevant. Don't paste a raw file list. If a draft PR was opened earlier, edit it (`gh pr edit`); otherwise create it (`create-pr`).

## Completion

**Preflight (required).** Before doing any workflow work, verify beads is set up:
`sh .claude/references/beads-preflight.sh`. If it exits non-zero, **stop** — do not
proceed without beads — and tell the user to run the `setup-beads` skill, then retry.

Commit the documentation changes (`Skill(git-commit)` first; stage explicit paths), push, and ready the PR (`gh pr ready` if it was a draft). When staging, **explicitly include durable docs authored earlier in the workflow that no task commit owns** — above all an **ADR from Define** under `docs/decisions/` (or the project's ADR dir). These are created with `Write` long before this step and are easy to leave untracked.

Before you ready the PR, confirm nothing durable is orphaned: `git status --porcelain` should show no untracked file that belongs in the repo (transient scratch is fine). A dangling ADR that the PR description links to is the classic miss — catch it here.

This is also `autorun`'s terminal step: ready the PR and **stop** — never merge or approve, that's the human's gate. File issues for any deliberately-deferred documentation and close out the feature epic — beads is the system of record. See [`.claude/references/beads.md`](../../references/beads.md) for the full model.
