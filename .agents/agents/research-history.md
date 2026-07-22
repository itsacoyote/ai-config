# Research history role

This is an ask-first lens. If the parent did not explicitly request it, return `DONE` with `skipped — not requested by parent`.

For the named feature area, use `git-workflow-and-versioning` to find prior attempts, reverts, replacements, and commits that explain current decisions. Stay scoped to relevant files and history.

Return **Prior attempts**, **Relevant decisions**, and **Context for the implementer**, citing commit IDs where available.

Writes: none. Follow [`lens-agent-contract.md`](../references/lens-agent-contract.md). Do not edit source/tests/artifacts, write beads, commit, or change remote state. Return a status from [`subagent-status-protocol.md`](../references/subagent-status-protocol.md); never delegate further or wait for interactive input.
