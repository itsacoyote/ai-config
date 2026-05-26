# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commits and PRs

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages and PR titles: `type(scope): description`. No `Co-Authored-By` trailers.

## Workflow entry point

Use the `/feature` skill to start or resume any feature. Do not invoke individual step agents directly unless explicitly asked to do so.

```text
/feature I want to build [idea]   # start a new feature
/feature                          # resume an in-progress feature or start fresh
```

The `/feature` skill owns all pipeline sequencing: step transitions, `context.yaml` updates, the spec approval gate, escalation handling, and the final PR URL announcement. Agents do their domain work and return — they do not invoke each other.

## Docs Directory

This project uses a `.docs/` directory for persistent context.

```text
.docs/
└── YYYY-MM-DD-<short-name>/        # Folder for a feature
  ├── artifacts/
    └── <artifacts>                 # Artifacts and resources for feature
  ├── output-artifacts/
    └── <implementation artifacts>  # Artifacts from implementation, like screenshots or recordings
  ├── context.yaml                  # Workflow state — read by every agent and the /feature orchestrator
  ├── 1_spec.md                     # Define step that outlines the specs, scope, constraints, validation etc
  ├── 2_research.md                 # Results of studying and identifying areas of code and domain
                                      to be affected by the feature
  ├── 3_plan.md                     # Step by step implementation details broken down into tasks
  └── 4_validate.md                 # Validation of implementation. QA, testing, revisions, etc
```

## context.yaml workflow fields

Every feature has a `context.yaml`. The `workflow` block tracks pipeline state:

- `current_step` — the active step name
- `completed_steps` — ordered list of steps that have finished
- `checkpoint` — free-text resume point within a step (written by agents, cleared on handoff)
- `escalated` — set to `true` by an agent that cannot resolve an issue after 3 attempts, or when `git push` fails; the orchestrator halts when it sees this
- `escalation_reason` — human-readable description of what caused the escalation

Only the `/feature` orchestrator writes `current_step` and `completed_steps`. Agents write `checkpoint`, `escalated`, and `escalation_reason`. When resuming after an escalation, the orchestrator resets `escalated` to `false` and `escalation_reason` to `""` before re-invoking the step.

## Per-step commit and push

Every pipeline agent (Define, Research, Plan, Implement, Validate, Document) commits its own output files — the step document, any artifacts produced, and the updated `context.yaml` — then pushes the feature branch before returning to the orchestrator. The orchestrator also commits and pushes `context.yaml` after each step transition.

This means:

- The remote feature branch is always in sync with local after each step boundary
- Every step has its own commit in the git history — you can revert any step independently
- `context.yaml` and the files it references are always consistent at every commit
- If a session ends between steps, resuming from another machine loses nothing

All commit messages follow Conventional Commits. Every agent invokes `Skill(git-commit)` before each `git commit`. No agent uses `git add -A` or `git add .` — only explicit file paths.

If `git push` fails (non-fast-forward, auth, network), the agent writes `workflow.escalated: true` and `workflow.escalation_reason` to `context.yaml` and returns. The orchestrator halts the pipeline and surfaces the failure. Resolve the remote state (e.g. `git pull --rebase`) and resume with `/feature`.

## GitHub tool preference

Always use the GitHub CLI (`gh`, `git`) for git and GitHub operations. Fall back to `mcp__github__*` tools only when the CLI is unavailable or cannot perform the required operation. Invoke `Skill(github-tool-preference)` before any `gh` or `mcp__github__*` call to confirm the right tool is chosen.

## MCP servers

This project ships `.mcp.json` with two servers:

- `playwright` — browser automation (used by the QA Reviewer)
- `github` — GitHub API for interactive use (requires `GITHUB_PERSONAL_ACCESS_TOKEN` in the environment); pipeline agents use `gh` CLI and `git` instead

Agent frontmatter declares which servers each agent needs via `mcpServers:`. Do not add server declarations to agents that do not need them. The only agent that currently declares `mcpServers` is `qa-reviewer.md` (playwright).
