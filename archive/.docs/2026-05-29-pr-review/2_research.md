# Research: PR Review Skill

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-05-29

## Summary

This research surveys the `.claude/skills/` and `.claude/agents/` trees to lock down exactly how the new `pr-review` skill should be structured. I read every `SKILL.md` in the repo to catalog frontmatter conventions, the `code-reviewer` agent's current contract, the `implement`/`validate` skills (which are the only existing skills that invoke an agent via the `Agent` tool), the `github-tool-preference` skill, and the `gh` CLI surface for `pr view`, `pr diff`, `pr comment`, and `repo view`. I also resolved the three open questions from the spec — triage UX, comment formatting, and the edit mechanism — with a concrete recommendation for each. No new gh subcommands or third-party libraries are needed; everything the skill requires already exists in the repo or in the local `gh` install (v2.92.0).

## Codebase Areas Affected

- `.claude/skills/pr-review/SKILL.md` — the new skill itself. New file. Must follow the conventions in the rest of `.claude/skills/`.
- `.claude/agents/code-reviewer.md` — read-only. The new skill invokes this agent unchanged and adapts the invocation to an external-PR context (no `3_plan.md`, plan alignment N/A).
- `.claude/skills/github-tool-preference/SKILL.md` — referenced. The new skill must invoke `Skill(github-tool-preference)` before each `gh` call to satisfy the project memory rule about gh-vs-mcp.
- `.claude/skills/git-commit/SKILL.md` — referenced. Not actually used here (the skill posts PR comments, it does not commit), but worth noting that nothing in the skill's output goes through git commits at all. Skipping `Skill(git-commit)` for this skill is correct.
- No production code paths are affected — this feature is entirely additive inside `.claude/skills/`.

## Reusable Code

### Existing skills with `argument-hint` + `$ARGUMENTS` (template for slash-command invocation)

Four skills already use the slash-command pattern the spec requires. Each declares `argument-hint:` in frontmatter and references `$ARGUMENTS` in the body. Copying this shape verbatim guarantees `/pr-review <pr-number>` will route the argument correctly:

- `.claude/skills/analyze-code/SKILL.md` — `argument-hint: "[file or directory path]"`, body opens with ``Survey `$ARGUMENTS` to understand…``.
- `.claude/skills/find-patterns/SKILL.md` — `argument-hint: [area, pattern type, or feature domain]`, body opens with ``Identify the conventions and patterns in `$ARGUMENTS`…``.
- `.claude/skills/web-search/SKILL.md` — `argument-hint: [library, API, or topic to search]`, body opens with ``Search the web for documentation or guidance on `$ARGUMENTS`.``
- `.claude/skills/feature/SKILL.md` — `argument-hint: "[feature idea or description]"`, body uses ``use `$ARGUMENTS` if provided, otherwise ask: "What do you want to build?"``.

All four follow the same convention for missing args: "If no target is provided, ask what to analyze." The spec's "ask for a PR number if none supplied" requirement maps directly to this pattern.

### Existing skills that invoke an agent (template for delegating to code-reviewer)

Only two skills declare `Agent` in `allowed-tools`, and both invoke `code-reviewer` (or its peers) the same way — by name, with a short prose handoff. These are the templates to copy:

- `.claude/skills/implement/SKILL.md` — `allowed-tools: Read Edit Write Bash(*) Agent`. Body: ``After every 300–500 lines, invoke the Code Reviewer agent before continuing to the next task. Pass the plan document so the Code Reviewer can check plan alignment.``
- `.claude/skills/validate/SKILL.md` — `allowed-tools: Read Bash(*) Agent`. Body: ``Invoke the Senior Reviewer agent. Pass the spec, plan, and full diff as context.``

The pattern is: list `Agent` in `allowed-tools`, then in prose say "Invoke the X agent. Pass [these things] as context." There is no formal protocol or wrapper — the model knows how to call the agent. Our skill says: invoke the `code-reviewer` agent and pass the PR diff, changed files, PR title, and PR body — plus an explicit note that this is an external PR with no `3_plan.md` and plan alignment is N/A.

### code-reviewer agent (consumed as-is)

`.claude/agents/code-reviewer.md` is the agent the skill delegates to. Key facts:

- **Frontmatter:** `name: code-reviewer`, `model: sonnet`, declares skills `agent-context`, `verify-correctness`, `verify-coherence`.
- **Default context-loading behavior** (its existing in-pipeline contract): reads `context.yaml` from a feature folder, checks out `feature.branch`, reads `3_plan.md`. For an external PR there is no feature folder and no plan. The agent's prompt is structured around two review axes — "the plan" and "engineering quality" — and only the second applies here.
- **Output shape:** A list of findings where each finding has Location (file + line/function), Problem (what is wrong and why it matters), and Fix (the specific change required). This is exactly the shape the spec assumes for the triage step. Reuse it without modification.
- **Approval string:** When everything is clean the agent returns `"Approved — continue implementation."` with a one-or-two-sentence summary. The `pr-review` skill should detect this and tell the user "No findings — nothing to triage." rather than walking through an empty checklist.
- **Severity language:** The agent prompt uses the phrase "proportionate" but does not assign explicit severity tags (CRITICAL/HIGH/MEDIUM/LOW) — that is the `security-review` skill's job, not the code-reviewer's. The `pr-review` skill should not invent severity tags; it presents findings as the code-reviewer returned them.

### gh CLI subcommands (consumed as-is)

`gh` 2.92.0 is installed. Every subcommand the skill needs already supports the flags we need — no shelling out to `curl` or `mcp__github__*`:

- `gh repo view --json nameWithOwner -q .nameWithOwner` — get the current repo's `owner/name`. Confirms the user is inside a GitHub repo before invoking the agent.
- `gh pr view <pr-number> --json number,title,body,author,state,baseRefName,headRefName,isDraft,url,files` — single call returns everything the agent needs for context. `state` confirms the PR is `OPEN` (per spec, closed/merged should report and stop). `files` returns the changed-file list with paths and line counts.
- `gh pr diff <pr-number>` — full unified diff text. Pipe straight to the code-reviewer agent.
- `gh pr diff <pr-number> --name-only` — alternative to `--json files` for just paths; redundant given we already get `files` from `pr view --json`. Use the `pr view` form.
- `gh pr comment <pr-number> --body "<text>"` — posts one top-level PR comment (an "issue comment" on the PR, not an inline review thread). Returns the comment URL on stdout. Exit non-zero on auth or API errors with the gh error on stderr.
- **Crucially:** `gh pr review --approve` and `gh pr review --request-changes` are real commands. They are exactly what the spec forbids the skill from calling. The skill must never construct a `gh pr review` invocation under any branch of its logic. Word the SKILL.md negative constraint to name both flags explicitly so the model has no ambiguity.
- `gh pr comment --body-file -` reads from stdin — useful if a finding body contains characters that are awkward to escape on a shell command line. Recommend the skill use `--body-file -` and pipe the finding text in, to avoid shell-quoting bugs on findings that contain backticks, dollar signs, or newlines.

### github-tool-preference skill

`.claude/skills/github-tool-preference/SKILL.md` is the project's canonical statement that `gh` and `git` are the defaults; `mcp__github__*` is fallback. The spec invokes this skill by name in Constraints. The new `pr-review` skill should invoke `Skill(github-tool-preference)` before each `gh` shell-out as the project memory rule requires.

## Gaps: What Needs to Be Created

- **New skill file** — `.claude/skills/pr-review/SKILL.md`. Nothing reusable: no existing skill handles "fetch a PR + delegate review + interactive triage + post." It is a new composition of existing pieces.
- **No new agent** — the spec is explicit that `code-reviewer` is consumed unchanged. The skill must provide the agent with an explicit "no `3_plan.md`, skip plan alignment" context note so the agent does not error out trying to read a feature folder. This is a prose instruction inside the skill, not an agent change.
- **No new template files** — unlike `define`/`plan`/`research`, this skill produces no document under `.docs/`. The "checklist" the spec mentions lives in the conversation only; it is never persisted. No `template.md` is needed alongside `SKILL.md`.
- **No new gh subcommand or third-party dep** — everything is in `gh` 2.92.0.

## Patterns and Conventions to Follow

### Frontmatter pattern (mandatory)

Across the 18 SKILL.md files I read, the frontmatter conventions are tight and consistent. Match them exactly:

- `name:` — kebab-case, matches the folder name (`pr-review`).
- `description:` — one sentence. Description-led skills (`security-review`, `frontend-ui-engineering`, `impeccable`) use a long descriptor that doubles as a routing hint for the model; pipeline skills (`define`, `research`, `plan`, etc.) use a single tight sentence. For a user-invoked slash-command skill, a tight sentence is the right register.
- `argument-hint:` — present on every slash-command skill that takes an argument. Format is `"[hint text]"` or `[hint text]`. Use `"[pr-number]"` for `pr-review`.
- `disable-model-invocation: true` — present on the orchestration skills (`feature`, `define`, `research`, `plan`, `implement`, `validate`, `agent-context`). It tells the model not to invoke the skill on its own initiative. **Recommend setting this for `pr-review`** — the spec is explicit that the skill is user-invoked and must never auto-fire. This is the strongest available signal to keep the model from "helpfully" running it.
- `allowed-tools:` — space-separated list. For `pr-review` the required set is `Read Bash(gh *) Bash(git *) Agent`. `Read` is needed if the skill ever wants to look at local files (probably not, but cheap to include). `Bash(gh *)` and `Bash(git *)` keep shell access scoped. `Agent` enables the code-reviewer invocation.

Do not invent fields. The repo does not use `version`, `user-invocable`, `mcpServers`, or `model` on skills except where they already appear (`impeccable` has `version`/`user-invocable`/`license`; `qa-reviewer` (an *agent*, not a skill) has `mcpServers`). Adding them to `pr-review` would be noise.

### Body structure pattern

Every skill body follows roughly the same structure:

1. **H1 with the skill display name.**
2. **One-paragraph statement of what the skill does**, often using `$ARGUMENTS` directly in the first sentence (see analyze-code, find-patterns, web-search).
3. **Optional sections** with H2s — `## When to Use`, `## Process` or `## Workflow`, `## Constraints`, `## Output`, `## See Also`.

For `pr-review`, the body needs at minimum: a one-paragraph statement of what the skill does, a workflow section walking through Fetch → Delegate → Triage → Post, a hard-bounded "What this skill will not do" section (matching the spec's Non-Goals), and an instructions block to the model about how to refuse approve/request-changes attempts.

### "Invoke X agent" handoff prose

The validate and implement skills don't use any formal markup to hand off to an agent — they just say "Invoke the X agent. Pass [Y] as context." in prose. Match that. Do not invent a JSON or YAML schema for the handoff. Do not pretend there is an inter-agent protocol that doesn't exist.

### Triage / interactive flow — no precedent in this repo

There is no existing interactive-triage skill in the repo. The `validate` skill loops over reviewer findings and fixes them, but it does not present findings to the user one at a time with keep/drop. The pattern for `pr-review` will be new. Two principles to follow from neighboring code:

- **Be explicit about state.** The validate skill is meticulous about "what the agent returned, what was applied, what is next" — the same energy applies to the triage checklist. Print the running state every time it changes, not just on request.
- **Never silently advance past a decision point.** The validate skill's "Green-suite gate" treats a passing verdict as a defect if the underlying e2e suite isn't actually green; it re-invokes rather than papering over. The `pr-review` skill's "post now" gate should be that strict — anything less than an unambiguous affirmative ("yes", "post", "ship it") is a no.

## Architectural Context

- **Skills are slash-commands once installed at `.claude/skills/<name>/SKILL.md`.** No additional registry, manifest, or import step. The harness picks them up by directory layout. This is why the spec's acceptance criterion #1 — "`.claude/skills/pr-review/SKILL.md` exists with valid frontmatter" — is essentially the entire installation step.
- **Skills delegate to agents declared under `.claude/agents/`.** The `Agent` entry in `allowed-tools` is the permission gate. The agent's frontmatter `model: sonnet` (for `code-reviewer`) means the review runs on Sonnet regardless of what model is running the parent skill — useful to know if review latency matters in UX.
- **There is no shared message bus or callback mechanism.** When the skill invokes the code-reviewer agent, control transfers to the agent until it returns. Findings come back as the agent's final message. The skill resumes from there in the same conversation. State (the triage checklist) lives entirely in the model's working context — the spec's "no disk persistence" requirement is the natural state, not something the implementer has to defend against.
- **`gh` runs as the current OS user with the credentials in `gh auth status`.** Comments are posted as that user. No `Co-Authored-By` is added by `gh` itself, so the spec's "no AI attribution" requirement is satisfied at the tool layer as long as the skill never adds attribution to the finding body.
- **`Skill(github-tool-preference)` is invoked, not imported.** This is a memory-rule mechanism: the model loads the skill text into its working context, which reinforces the gh-first policy. The new skill should call it once near the top of the workflow and once in the constraints section, the same way `implement` and `validate` reference their dependent skills.

## Key Insights for the Planner

- **The skill is a single `SKILL.md` file.** No `template.md`, no `scripts/`, no `references/` directory. Keep the file map to one entry: `.claude/skills/pr-review/SKILL.md` under New Files. The Plan should reflect this minimalism — do not invent supporting files.

- **The hard guarantees ("never approve", "never request changes", "never auto-post", "never persist") are guarantees about what the skill's prose tells the model not to do.** There is no enforcement layer below the model. That makes the wording load-bearing. The Plan should require the skill body to contain explicit, named negatives — "Do not call `gh pr review --approve` under any circumstance" and "Do not call `gh pr review --request-changes` under any circumstance" — rather than abstract phrasing like "the skill won't approve PRs." Negative constraints that name the exact shell command are the most effective signal we have.

- **The code-reviewer agent expects a feature folder and a `3_plan.md` it can read.** Without an explicit "this is an external PR, no plan exists, plan alignment is N/A" instruction in the handoff, the agent's gate will look for `context.yaml` and fail. The skill's invocation text must call this out. Suggested wording for the Plan to adopt verbatim: "This is an external PR review, not a pipeline feature. No `3_plan.md` exists. Skip plan alignment entirely and review against engineering quality only (correctness, security, code quality, test quality). Here is the PR title, body, changed-file list, and full diff. Return findings in your standard Location / Problem / Fix shape."

- **The skill's input surface is small (one positive-integer PR number) and its failure modes are well-defined.** Validation is a four-line decision tree: missing → ask; non-numeric → error; numeric but PR not found / not accessible → report gh error and stop; numeric and accessible → continue. Plan should enumerate these as explicit branches with the exact prompt/error text.

- **`gh pr comment --body-file -` is safer than `--body "<text>"` for finding bodies.** Findings can contain backticks, dollar signs, code fences, and newlines. Shell-escaping all of those correctly inside a `--body` flag is a known bug factory. Recommend the Plan specify that each post is `printf '%s' "$finding" | gh pr comment <pr-number> --body-file -` or equivalent, with `--body-file -` instead of `--body "<text>"`.

- **There is no precedent in this repo for an interactive multi-turn UX inside a single skill invocation.** The skill will need to define the UX itself: prompt format, navigation grammar ("show checklist", "go back to finding 3"), and what counts as an explicit affirmative. The Plan must lock these down precisely — vague phrasing like "ask the user to confirm" leaves room for the model to interpret silence as consent. Wording suggestion: a literal table of accepted inputs and what each does, so the model has a deterministic decision surface.

- **No coverage, no tests, no commits.** This skill produces no committed code in the user's repo. Coverage and test-suite mechanics from the standard Implement workflow do not apply. The Plan should not include tasks for "add unit tests" or "run linter" — there is nothing to lint or test except the markdown file itself.

## Artifacts

None produced during this research. All findings live in this document; no diagrams, schemas, or sample files were necessary.

## Open Questions

Three open questions were carried forward from the spec. Recommendations follow.

- **Triage UX — one-by-one vs. batch.** Default to one-by-one. Add a single optional opt-in: if the user replies `batch` (or `review all`) at the very first prompt of the triage phase, switch to batch mode where the skill prints all findings numbered and the user replies with a single multi-line decision list (e.g. `1 keep, 2 drop, 3 edit, 4 keep`). For `edit`, the skill drops back into per-finding mode for those specific findings. **Rationale:** one-by-one is the right default because it forces the reviewer to consider each finding in isolation, which is the whole point of triage. Batch is the right escape hatch for >10-finding reviews where one-by-one becomes tedious. Anything more elaborate (e.g. `keep with comment`, severity-based filters) is YAGNI for the first version. **Decide in Plan, not Research.**

- **Comment formatting.** Use a standard `**path/to/file:line** — finding text` prefix. The code-reviewer's existing output already includes a Location field; surface it visibly so a reviewer scrolling the PR page can jump to the right place. If the code-reviewer returned a function name instead of a line ("`useAuthToken` hook"), the prefix becomes `**path/to/file** (`useAuthToken`) — finding text`. **Rationale:** GitHub renders the `**file:line**` prefix as bold inline text and reviewers immediately recognize it as a location anchor. Without a prefix, the comment reads as floating commentary with no obvious referent. The Plan should specify the exact format and pick a canonical separator (the em-dash `—` matches the project's writing style in `CLAUDE.md` and other skill files).

- **Edit mechanism.** Use inline rewrite. When the user replies `edit` on a finding, the skill prints the current finding text in a fenced block and asks: "Paste the revised version." The user pastes back the full revised text. The skill stores that as the new finding body, displays it back for confirmation, and then proceeds to keep/drop on the revised version. **Rationale:** conversational editing ("change the second paragraph to say X") is high-touch and error-prone; both the user and the model have to keep two versions in mind. Inline rewrite gives the user full control with no ambiguity about what will be posted. The Plan should specify this and explicitly forbid the model from interpreting the revised text — it is posted verbatim. The only post-processing is the file:line prefix described above, and that is applied uniformly to every comment regardless of whether it was edited.
