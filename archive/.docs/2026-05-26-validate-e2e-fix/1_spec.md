# Spec: Validate agent runs and fixes e2e tests before handoff

**Date:** 2026-05-26
**Status:** Draft

## Summary

The Validate step in the `/feature` pipeline is supposed to be the last gate before a PR is opened for human review. Today, it ships PRs with failing e2e tests because neither the Validate agent, the validate skill, nor the QA Reviewer agent ever actually executes the e2e suite — they only review test files as artifacts. This feature rewrites the QA Reviewer and the validate skill so that QA runs the full e2e suite, fixes any failures it finds, re-runs the suite, and only approves once every test passes. The Document step is only reachable when QA's verdict is "approved with a clean test run."

## Problem Statement

Users running the `/feature` pipeline are receiving PRs in human review with failing e2e tests. The user is then forced to manually prompt Claude with "run the e2e tests and fix them" after the pipeline has already declared the feature complete — which defeats the purpose of having a Validate step at all.

Reading the current agent and skill definitions, the root cause is that nothing in the validate pipeline ever executes the e2e suite:

- `.claude/agents/qa-reviewer.md` instructs the QA Reviewer to "review test files," "map user stories to e2e tests," and "capture visual evidence once all tests pass" — but never says to *run* the tests. The "once all tests pass" precondition is asserted, not verified.
- `.claude/skills/validate/SKILL.md` mentions running the test suite only as a sanity check after Senior Reviewer fixes. There is no gate at the end of QA that requires a green e2e run.
- `.claude/agents/validate.md` reads the validate skill verdict and proceeds. Because the skill never demands a green suite, the agent never blocks on one.

The net effect: the QA Reviewer can approve a feature whose e2e tests have never been run on this branch, and the Validate agent will hand off to Document. Failing tests then become a problem the human reviewer discovers — or, more often, that CI discovers after the PR is open.

## Goals

- QA Reviewer executes the project's full e2e test suite on every Validate run, before approving.
- When the suite fails, the QA Reviewer enters a fix loop: diagnose the failure, fix the code or the test (whichever is actually wrong), re-run the suite, and only exit when the suite is green.
- The validate skill enforces a green-suite gate: QA cannot return "approved" unless the most recent e2e run on the current commit passed.
- The Validate agent will not hand off to Document while QA's last run was red.
- When QA cannot get to green after N attempts, it escalates rather than approving a broken build.

## Non-Goals

- Changing the Senior Reviewer's responsibilities. Senior review remains a code-and-design audit; it does not own test execution.
- Adding new test frameworks, writing new tests beyond what's required to cover the spec, or changing the project's existing e2e configuration.
- Running unit or integration tests as part of QA's loop. Those are expected to be green from the Implement step; QA continues to inspect their quality but does not own re-running them as the gating signal. (If a project's `test` command runs unit + e2e together, that's fine — the gating signal is "the full suite passes.")
- Capturing performance metrics, flake detection, or quarantining flaky tests. If a test is flaky, QA fixes it or escalates; it does not skip it.
- Modifying behavior for projects that have no e2e framework configured. In that case QA flags the gap as it does today and the pipeline proceeds — this spec does not introduce e2e infrastructure.

## User Stories

- As a developer running `/feature`, I want the pipeline to refuse to open a PR for human review while e2e tests are failing, so I never have to manually prompt Claude to run tests after the workflow says it's done.
- As a developer reviewing a PR produced by `/feature`, I want to trust that every PR I see has a green e2e run on its head commit, so the human review can focus on design and intent rather than basic correctness.
- As a developer whose feature triggers a real e2e failure during QA, I want QA to attempt a bounded number of fixes, commit each attempt, and re-run the suite — so genuine bugs are caught and resolved inside the pipeline.
- As a developer whose feature reveals a deeper issue QA cannot fix in 3 attempts, I want QA to escalate cleanly with a summary of what was tried, so I can resume from a known state instead of debugging which "approval" is real.

## Requirements

### QA Reviewer agent (`.claude/agents/qa-reviewer.md`)

- The agent must run the project's e2e test suite as the first action in its review, before any other QA work.
- The agent must detect the correct e2e command by inspecting the project (e.g. `package.json` scripts, `Makefile`, project README). If no e2e command can be identified, the agent records "no e2e framework configured" as a gap and proceeds with the rest of QA — it does not invent a command.
- When an e2e run fails, the agent must:
  1. Read the failure output and identify the failing test(s) and root cause.
  2. Decide whether the bug is in the production code or in the test itself (a test asserting incorrect behavior is also a defect).
  3. Apply the fix using the same diff-aware standards as Implement: respect the spec, do not introduce unrelated changes, do not weaken assertions to make tests pass.
  4. Commit the fix on the feature branch with a conventional-commits message (`fix(<scope>): <description>` or `test(<scope>): <description>`), invoking `Skill(git-commit)` first.
  5. Re-run the full e2e suite from a clean state.
- The fix-and-rerun loop runs up to **3 attempts**. If the suite is still red after 3 attempts, the agent must stop fixing and return an escalation verdict — it must not approve.
- The agent must record, for each attempt: the failing tests, the diagnosed cause, the fix applied, and the result of the re-run. This goes into the verdict so the Validate agent can write it into `4_validate.md`.
- Evidence capture (screenshots/videos) only runs **after** the suite is green. The "once all tests pass" precondition becomes a real check, not an assertion.
- The agent's verdict has exactly three terminal states:
  - **Approved** — every e2e test passed on the current HEAD, coverage ≥ 80%, no gaps. Required state for proceeding.
  - **Gaps** — tests pass but coverage or test-quality gaps exist. Sent back to the validate skill for a fix iteration (existing behavior).
  - **Escalated** — could not reach a green suite in 3 attempts, or no e2e framework was configured and the spec required user-facing behavior to be verified. Pipeline halts.

### Validate skill (`.claude/skills/validate/SKILL.md`)

- Round 2 (QA Review) must explicitly document the e2e-execution responsibility, the 3-attempt fix loop, and the green-suite gate.
- After QA returns, the skill must verify the verdict came from a run whose final state was "all e2e tests passed on HEAD." If QA returns "approved" without that, the skill treats it as a defect and re-invokes QA with the gap called out.
- The completion step must include, in the validation summary, the count of e2e fix iterations and the final e2e result.

### Validate agent (`.claude/agents/validate.md`)

- The escalation block must be extended to cover the e2e-failure case: when QA escalates because it could not reach a green suite, the agent writes the standard escalation to `context.yaml` with `escalation_reason` listing the failing tests, the 3 attempted fixes, and the suspected root cause.
- The `4_validate.md` template must include an "E2E Test Run" section listing the final command, the result, and the number of fix iterations QA performed.

### Cross-cutting

- All commits made by QA during the fix loop follow conventional commits, are pushed alongside QA's existing push, and contain no `Co-Authored-By` trailers (per project `CLAUDE.md`).
- QA never uses `git add -A` or `git add .` — staged paths are explicit.
- If `git push` fails after QA commits, the standard push-failure escalation applies (same pattern as the other agents).

## Constraints

- The pipeline is sequential. QA cannot run in parallel with Senior Review, and Document cannot start while Validate has not completed cleanly. This spec preserves that order.
- The fix iteration cap is **3**, matching the convention used by every other pipeline step and the existing validate skill. Do not introduce a different cap for e2e.
- The agent must work with whatever e2e framework the project uses (Playwright, Cypress, native test runners, etc.). It must not assume one framework — it detects from the project.
- The agent cannot introduce skips, `.only`, `.skip`, `xtest`, `xit`, or test quarantining as a fix. Making a red test green by removing it is not a fix.
- All changes stay within `.claude/agents/qa-reviewer.md`, `.claude/skills/validate/SKILL.md`, and `.claude/agents/validate.md`. No new agents, no new skills.

## Acceptance Criteria

- [ ] `.claude/agents/qa-reviewer.md` instructs the QA Reviewer to run the e2e suite as the first action, before any review activity.
- [ ] `.claude/agents/qa-reviewer.md` defines a 3-attempt fix-and-rerun loop with the exact diagnose → fix → commit → re-run sequence, including a conventional-commits message format.
- [ ] `.claude/agents/qa-reviewer.md` defines the three terminal verdict states (Approved, Gaps, Escalated) and makes "all e2e tests pass on HEAD" a hard prerequisite for Approved.
- [ ] `.claude/agents/qa-reviewer.md` prohibits skipping, removing, or weakening tests as a path to green.
- [ ] `.claude/agents/qa-reviewer.md` only triggers evidence capture after the suite is green.
- [ ] `.claude/skills/validate/SKILL.md` Round 2 documents the e2e execution responsibility and the green-suite gate, and refuses to accept an "approved" verdict that wasn't backed by a green run on HEAD.
- [ ] `.claude/skills/validate/SKILL.md` completion summary includes e2e fix iteration count and final e2e result.
- [ ] `.claude/agents/validate.md` escalation block handles the e2e-failure case with a concrete `escalation_reason` template, and the `4_validate.md` template adds an "E2E Test Run" section.
- [ ] All file edits use conventional commits with no `Co-Authored-By` trailers, and stage explicit paths only.
- [ ] A dry-run of the updated pipeline against a feature with an intentionally-failing e2e test results in either a green suite (after fixes) or a clean escalation — never a handoff to Document with red tests.

## Open Questions

None — the design above is fully specified by the problem statement and the existing pipeline conventions. If implementation surfaces ambiguity (e.g. how to detect the e2e command in a project that uses neither `package.json` nor a `Makefile`), the Plan step will resolve it before code is written.
