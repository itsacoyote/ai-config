# Neutral isolated-role contracts

`roles.json` is the versioned, canonical policy for isolated roles. The adjacent Markdown files are prompt content only. Codex adapters and the Pi runner must parse the manifest and must not infer policy from Markdown, frontmatter, filenames, or Claude agent files.

## Schema version 1

Top-level fields are exact:

- `version`: integer `1`.
- `contracts.qa_result`: the QA result schema filename, resolved in this directory.
- `roles`: ordered role objects.

Each role has exactly:

- `name`: unique lowercase kebab-case identifier.
- `description`: neutral purpose and trigger.
- `prompt`: local Markdown filename; always `<name>.md`.
- `skills`: complete portable skills that a worker must preload. For Pi, preload each full `SKILL.md`; a skill name alone is not sufficient.
- `mode`: one of the modes below.
- `tools`: capability names used by adapters and runners. These document required capability; skill/tool metadata is not a portable security boundary.

Unknown versions, fields, modes, tools, duplicate names, unresolved prompts/skills/links, or policy violations are invalid. Consumers must stop before dispatch and surface validation errors. They must not guess defaults or silently drop unknown data.

## Modes

- `read-only`: may inspect and evaluate; writes no source, tests, generated artifacts, beads, commits, or remote state.
- `verification`: may run checks and write only generated test/evidence artifacts such as reports, screenshots, and traces. It never edits source or test definitions.
- `implementation`: may edit source and named tests inside one task's scope and may commit. It never pushes. `implementer` is the only role in this mode and the only role with `source-write`.

Allowed capabilities are `read`, `search`, `shell`, `web`, `browser`, `source-write`, `test-artifact-write`, `evidence-artifact-write`, and `commit`.

## QA contract

`qa-review` emits schema-version-1 JSON validated against `qa-result.schema.json`. Consumers use `.agents/scripts/validate-qa-result.py` before acting:

- `APPROVED` passes.
- An actionable `FIX_REQUIRED` on attempts 1–2 dispatches exactly one serialized implementer, then fresh QA reruns with an incremented attempt.
- Attempt-3 `FIX_REQUIRED`, `BLOCKED`, malformed output, unknown versions, and non-actionable fixes block without implementation dispatch.

Legacy wording is mapped explicitly by the validator: `Approved` to `APPROVED`, `Gaps` to `FIX_REQUIRED`, and `Blocked` to `BLOCKED`.

## Consumer rules

1. Run `.agents/scripts/validate-roles.py` before generating adapters or dispatching a worker.
2. Select the role by exact `name` from the manifest.
3. Apply mode/tool policy from JSON only.
4. Load the referenced prompt and every declared skill completely.
5. Keep provider model aliases and harness-specific dispatch syntax in adapters, never in this manifest or its prompts.
6. Treat worker status/output as data. Invalid results return to the parent as blocked; they never widen permissions.
