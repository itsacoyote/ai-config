# Plan: Validate agent runs and fixes e2e tests before handoff

**Spec:** [1_spec.md](1_spec.md)
**Research:** [2_research.md](2_research.md)
**Date:** 2026-05-26

## Overview

This is a documentation-only change across three Markdown files. No code, no tests in the traditional sense — "tests" here are the spec's acceptance criteria, each of which must be observable in the final text of one of the three files. The Implement agent will edit prose; verification is by grepping the modified files for the required content and by reading them end-to-end for coherence.

Three open questions from research are resolved up front so the implementer never has to guess:

- **E2E command detection precedence.** Order: (1) explicit `test:e2e` script in `package.json`; (2) `e2e` script in `package.json`; (3) `e2e` target in a `Makefile`; (4) any command the project README documents as the e2e command. First match wins. If none match, record "no e2e framework configured" as a gap and skip running — never invent a command.
- **Missing runtime handling.** If detection finds a configured command but the runtime is unavailable (e.g. `package.json` has `test:e2e` but `npm`/`pnpm`/`yarn` is not on PATH, or `make` is missing), this is an **Escalated** verdict — not a "no e2e configured" gap. A missing runtime indicates broken local setup, which the user must fix; QA must not silently approve.
- **Coverage re-check placement.** Coverage is re-verified once, **after** the e2e suite is green — not interleaved with the fix loop. This is stated explicitly in both the QA Reviewer's Approved-state preconditions and in the validate skill's Round 2 description.

## File Map

All decomposition decisions are made here. Every file below appears in the tasks that follow.

### New Files

None. The spec mandates that all changes stay within the three existing files.

### Modified Files

| File | What Changes | Why |
|------|-------------|-----|
| `.claude/agents/qa-reviewer.md` | (1) Insert "E2E Execution" as the first sub-section under "Review Process," with the detection-precedence rule, the run-first directive, the 3-attempt fix-and-rerun loop with per-attempt logging, and the diagnose → fix → commit → re-run recipe. (2) Replace the two-state "Verdict" section with a three-state contract: Approved, Gaps, Escalated, with explicit preconditions for each. (3) Gate "Evidence capture" behind the Approved branch by moving it after the new Verdict section and adding a one-line precondition. (4) Extend "Non-negotiables" to forbid `.skip` / `.only` / `xtest` / `xit` / `it.skip` / `test.skip` / deleting tests / weakening assertions as a path to green. | Spec §QA Reviewer; acceptance #1–#5 |
| `.claude/skills/validate/SKILL.md` | (1) Add a new paragraph at the top of "Round 2 — QA Review" naming QA's e2e execution responsibility, referencing (not redefining) the QA agent's internal 3-attempt e2e fix loop, and making clear the loop is independent of the skill's own Round 2 fix-iteration cap. (2) Add a "Green-suite gate" paragraph immediately after the existing "If the QA Reviewer returns issues" block: if QA returns Approved but the final state was not "all e2e tests passed on HEAD," treat it as a defect and re-invoke QA with the gap called out. (3) Add a bullet to "Completion" listing the e2e fix iteration count and final e2e result (green / escalated). | Spec §Validate skill; acceptance #6–#7 |
| `.claude/agents/validate.md` | (1) Update the embedded `4_validate.md` template (lines 30–58) to insert an "E2E Test Run" section between "QA Review" and "Evidence," with three fields: final e2e command, result, fix iterations. (2) Add a new sibling escalation block after "If the skill cannot complete" titled "If QA cannot reach a green e2e suite," using the standard `workflow.escalated: true` shape but with an `escalation_reason` template specialized to list: the failing tests, the 3 attempted fixes (each with diagnosis and fix-type), and the suspected root cause. | Spec §Validate agent; acceptance #8 |

### Deleted Files

None.

---

## Implementation Tasks

Tasks are ordered so that the file with the most authoritative new contract — the QA Reviewer agent — is updated first. The validate skill then references the contract the QA agent now exposes. The validate agent ties them together with its template and escalation. The final task verifies cross-file consistency, since the three files must use identical verdict-state vocabulary.

For documentation tasks, "Tests" lists the observable acceptance criteria the implementer can grep for or read for in the modified file. Each task ends with one commit; QA fix-loop commits are not produced during implementation — they're produced at runtime by the QA agent when this feature is in use.

---

### Task 1: Rewrite QA Reviewer's Review Process to run e2e first and own a 3-attempt fix loop

**Files:** `.claude/agents/qa-reviewer.md`

**Tests (acceptance criteria observable in the file after this task):**

```
describe('qa-reviewer.md — Review Process', () => {
  it('opens "Review Process" with an "E2E Execution" sub-section before any other audit')
  it('states detection precedence: package.json test:e2e → package.json e2e → Makefile e2e → README-documented command → "no e2e framework configured" gap')
  it('forbids inventing an e2e command when no match is found')
  it('classifies a missing runtime (e.g. package.json has test:e2e but npm is absent) as Escalated, not as a gap')
  it('directs the agent to run the detected command as the first action, before any review activity')
  it('defines a fix loop with five ordered steps: diagnose → decide code-vs-test → fix → commit → re-run')
  it('caps the fix loop at exactly 3 attempts')
  it('requires the fix commit to invoke Skill(git-commit) first')
  it('specifies the commit message template: fix(<scope>): <description> for code defects, test(<scope>): <description> for test defects')
  it('requires per-attempt logging of failing tests, diagnosed cause, fix applied, and re-run result, and routes that log into the verdict')
  it('forbids git add -A and git add . — explicit paths only')
})
```

**Implementation:**

1. Open `.claude/agents/qa-reviewer.md`.
2. Insert a new sub-section `**E2E Execution (first action):**` directly after the line `Pull the full diff and read \`1_spec.md\` alongside the test files.` and before `**Coverage audit:**`. Content of the new sub-section:
   - One sentence stating "run before any other QA work."
   - Detection-precedence list (1) `package.json` `test:e2e` script, (2) `package.json` `e2e` script, (3) `Makefile` `e2e` target, (4) command documented in the project README. First match wins. If none match, record "no e2e framework configured" as a gap and skip running. Never invent a command.
   - Missing-runtime rule: if a command is detected but the runtime binary is unavailable, return the **Escalated** verdict (forward reference to the new Verdict section).
   - Single-line directive: run the detected command from the repository root before any other review activity.
3. Immediately after the E2E Execution sub-section, insert `**E2E fix loop (when the suite fails):**`. Content:
   - Numbered list, exactly five steps:
     1. Diagnose: read the failure output, identify the failing test(s) and the root cause.
     2. Decide: is the bug in production code or in the test itself?
     3. Fix: apply the fix. Do not weaken assertions, do not skip, do not quarantine.
     4. Commit: invoke `Skill(git-commit)` first, then `git add <explicit paths>` (never `-A` or `.`), then `git commit -m "fix(<scope>): <description>"` when production code was wrong or `git commit -m "test(<scope>): <description>"` when the test was wrong.
     5. Re-run: run the full e2e suite from a clean state.
   - Single sentence: "Repeat up to 3 attempts. If still red after attempt 3, return the **Escalated** verdict — do not approve."
   - Per-attempt logging requirement: record for each attempt the failing tests, the diagnosed cause, the fix applied, and the re-run result. This log flows into the verdict, and from there into `4_validate.md`.
   - Note: in-loop commits accumulate locally; the terminal `git push` is owned by the Validate agent and flushes them.
4. Do not touch Coverage audit, Unit test quality, Integration test quality, or E2E test quality sub-sections in this task.

**Commit:** `docs(qa-reviewer): add e2e execution and 3-attempt fix loop`

---

### Task 2: Rewrite QA Reviewer's Verdict to a three-state contract and gate Evidence capture on Approved

**Files:** `.claude/agents/qa-reviewer.md`

**Tests:**

```
describe('qa-reviewer.md — Verdict', () => {
  it('defines exactly three terminal verdict states named Approved, Gaps, and Escalated')
  it('makes Approved require all three preconditions: every e2e test passed on the current HEAD, coverage ≥ 80%, no gaps')
  it('routes Gaps back to the validate skill for a fix iteration (existing behavior preserved)')
  it('routes Escalated to the validate agent when the e2e fix loop hit 3 attempts without green, or when no e2e framework was configured and the spec required user-facing behavior to be verified')
  it('includes the per-attempt fix log in the Escalated verdict payload')
})

describe('qa-reviewer.md — Evidence capture', () => {
  it('lives below the Verdict section, structurally after the Approved state is defined')
  it('opens with a precondition sentence that it runs only when the Approved verdict applies')
  it('still flags "no e2e framework set up" as a gap rather than silently skipping')
})

describe('qa-reviewer.md — Non-negotiables', () => {
  it('forbids .skip, .only, xtest, xit, it.skip, test.skip, deleting tests, and weakening assertions as a path to green')
})
```

**Implementation:**

1. In `.claude/agents/qa-reviewer.md`, replace the current `## Verdict` section (the two-state "If there are gaps" / "If tests pass" structure) with a three-state contract:
   - `**Approved**` — preconditions: every e2e test passed on the current HEAD; coverage ≥ 80%; no gaps. State the exact phrasing of the approval line: "QA approved." One short paragraph on coverage level and what was verified.
   - `**Gaps**` — coverage or test-quality gaps exist but e2e is green. List every gap with Type / What's missing / Required test (preserve the current gap-listing format).
   - `**Escalated**` — either (a) the e2e fix loop hit 3 attempts without reaching green, or (b) no e2e framework was configured and the spec required user-facing behavior to be verified. Payload includes the per-attempt fix log from Task 1.
2. Move the entire `## Evidence capture` section to immediately after the new `## Verdict` section. Add a one-line opening sentence: "Evidence capture runs only when the Approved verdict applies — green e2e suite on HEAD." Leave the body of the Evidence capture instructions otherwise unchanged.
3. Extend the existing `## Non-negotiables` paragraph with a new sentence enumerating the forbidden patterns: `.skip`, `.only`, `xtest`, `xit`, `it.skip`, `test.skip`, deleting tests, and weakening assertions. Phrase it as "Making a red test green by removing it, skipping it, or weakening its assertions is not a fix." Keep the existing "coverage theater" and "fake tests" language intact.

**Commit:** `docs(qa-reviewer): add three-state verdict and gate evidence on green suite`

---

### Task 3: Add e2e responsibility, green-suite gate, and e2e-iteration summary to validate skill

**Files:** `.claude/skills/validate/SKILL.md`

**Tests:**

```
describe('validate/SKILL.md — Round 2', () => {
  it('opens Round 2 with a paragraph stating QA executes the e2e suite as its first action')
  it('names the QA agent\'s internal 3-attempt e2e fix loop as the source of truth, without redefining the loop here')
  it('clarifies that the skill\'s own Round 2 fix-iteration cap of 3 is independent of QA\'s internal e2e fix loop')
})

describe('validate/SKILL.md — Green-suite gate', () => {
  it('adds a paragraph after the "If the QA Reviewer returns issues" block that handles the case where QA returns Approved but the final state was not all e2e tests passed on HEAD')
  it('treats such an "Approved" verdict as a defect and re-invokes QA with the gap called out')
})

describe('validate/SKILL.md — Completion', () => {
  it('includes a bullet stating the number of e2e fix iterations and the final e2e result (green / escalated)')
})
```

**Implementation:**

1. Open `.claude/skills/validate/SKILL.md`.
2. Immediately under the `### Round 2 — QA Review` heading and before the line `Once the Senior Reviewer has approved, invoke the QA Reviewer agent.`, insert a paragraph:
   - Sentence 1: "QA's first action is to run the project's full e2e suite. On failure, QA enters its own 3-attempt fix-and-rerun loop, defined in `.claude/agents/qa-reviewer.md`."
   - Sentence 2: Note that QA's internal e2e fix loop (cap 3) is independent of this skill's own Round 2 fix-iteration cap (also 3). Both apply; both are uniform across the pipeline.
3. After the existing five-step `If the QA Reviewer returns issues:` block and the line `If the same issues persist after 3 attempts, stop. Return a clear summary as above.`, insert a new `**Green-suite gate:**` paragraph:
   - Single statement: if QA returns the **Approved** verdict but the final state was not "all e2e tests passed on HEAD," treat the verdict as a defect. Re-invoke QA with the gap called out (e2e not actually run, or not actually green). This re-invocation counts against the same 3-iteration Round 2 cap.
4. Under `## Completion`, add a new bullet between the QA review bullet and the findings bullet: "Number of e2e fix iterations performed by the QA Reviewer and the final e2e result (green / escalated)."
5. Do not modify Round 1 or the Senior Code Review block.

**Commit:** `docs(validate): document e2e execution responsibility and green-suite gate`

---

### Task 4: Extend Validate agent template with E2E Test Run section and add e2e-failure escalation block

**Files:** `.claude/agents/validate.md`

**Tests:**

```
describe('validate.md — 4_validate.md template', () => {
  it('inserts an "## E2E Test Run" section between "## QA Review" and "## Evidence"')
  it('exposes three fields: final e2e command, result (green / escalated / not configured), and number of fix iterations')
})

describe('validate.md — E2E failure escalation', () => {
  it('adds a new escalation block titled "If QA cannot reach a green e2e suite" after the existing "If the skill cannot complete" block')
  it('uses the same workflow.escalated: true / escalation_reason yaml shape as the other escalation blocks')
  it('templates escalation_reason to list: the failing tests, the 3 attempted fixes (each with diagnosis and fix-type), and the suspected root cause')
})
```

**Implementation:**

1. Open `.claude/agents/validate.md`.
2. In the embedded `4_validate.md` template (the fenced markdown block currently spanning lines 30–58), insert a new section between `## QA Review` (and its sub-content) and `## Evidence`:
   ```markdown
   ## E2E Test Run

   **Command:** <the detected e2e command, e.g. `pnpm test:e2e`>
   **Result:** <green / escalated / not configured>
   **Fix iterations:** N
   ```
   Place it after the QA Review block (after the "Findings and fixes" bullet) and before `## Evidence`.
3. After the existing `## If the skill cannot complete` section (which currently ends at line 101 with "Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this."), append a new sibling section:
   ```markdown
   ## If QA cannot reach a green e2e suite

   If the QA Reviewer returns the **Escalated** verdict because its 3-attempt e2e fix loop could not reach a green suite, write the escalation to `context.yaml` and return:

   ```yaml
   # Merge into existing workflow block — do not replace other fields
   workflow:
     escalated: true
     escalation_reason: |
       QA could not reach a green e2e suite after 3 fix attempts.
       Failing tests: [list each failing test by name]
       Attempt 1: [diagnosis] — [fix applied, fix(...) or test(...)]
       Attempt 2: [diagnosis] — [fix applied]
       Attempt 3: [diagnosis] — [fix applied]
       Suspected root cause: [QA's assessment]
   ```

   Do not notify the user directly. The workflow orchestrator will halt the pipeline and surface this.
   ```
4. Do not modify the Gate, Workflow, "After the workflow completes," or Push-failure escalation sections.

**Commit:** `docs(validate): add e2e test run section and e2e-failure escalation`

---

### Task 5: Verify cross-file vocabulary consistency

**Files:** `.claude/agents/qa-reviewer.md`, `.claude/skills/validate/SKILL.md`, `.claude/agents/validate.md`

**Tests:**

```
describe('cross-file consistency', () => {
  it('uses the exact tokens "Approved", "Gaps", "Escalated" in qa-reviewer.md, validate/SKILL.md, and validate.md')
  it('uses the exact phrase "all e2e tests passed on HEAD" in qa-reviewer.md and validate/SKILL.md for the green-suite condition')
  it('uses the exact phrase "3 attempts" (not "three attempts" or "3 iterations") for the e2e fix loop cap in all three files')
  it('uses Skill(git-commit) (with parentheses, capitalized exactly as elsewhere) in qa-reviewer.md\'s fix-loop step 4')
  it('uses conventional-commits prefixes fix(<scope>) and test(<scope>) — lowercase, parens, colon-space — in qa-reviewer.md and in the validate.md escalation template')
})
```

**Implementation:**

1. After Tasks 1–4 are committed, re-read all three files end-to-end.
2. Grep each file for the three verdict tokens (`Approved`, `Gaps`, `Escalated`) and confirm they appear with the exact capitalization above. Fix any drift in place.
3. Grep each file for the green-suite phrase and confirm it reads `all e2e tests passed on HEAD` everywhere it is used.
4. Grep each file for the cap phrase and confirm it reads `3 attempts` (not "three" or "three (3)").
5. Confirm `Skill(git-commit)` is referenced verbatim in qa-reviewer.md's fix-loop step 4.
6. Confirm the conventional-commits prefixes are written as `fix(<scope>):` and `test(<scope>):` in qa-reviewer.md and that the validate.md escalation template uses the same prefixes when describing fix attempts.
7. If any consistency drift is found, fix it. This task may produce zero edits if Tasks 1–4 were precise — in that case, no commit is created and the task is a no-op closing check.

**Commit (only if edits were needed):** `docs: align e2e verdict vocabulary across qa-reviewer, validate skill, validate agent`

---

## Out of Scope

The following are explicitly excluded from this implementation, mirroring the spec's non-goals and constraints:

- Modifying the Senior Reviewer agent or its responsibilities — senior review remains a code-and-design audit and does not own test execution.
- Adding new test frameworks, writing new tests beyond what's required to cover this feature's documentation, or changing any project's existing e2e configuration.
- Running unit or integration tests as part of QA's loop — the gating signal is the full e2e suite. (If a project's `test` command happens to run both, that's fine, but the spec language stays scoped to "e2e suite.")
- Performance metrics, flake detection, or quarantining flaky tests.
- Introducing a new agent or skill — all three files in the file map are existing files, and the spec constraint forbids new ones.
- Touching `.claude/agents/implement.md`, `.claude/skills/feature/SKILL.md`, `.claude/agents/senior-reviewer.md`, or any other agent/skill. Those were read in research only as references for patterns.
- Promoting `1_spec.md` from `**Status:** Draft` to `**Status:** Approved`. The orchestrator already advanced past the spec gate; updating the status field is not in this feature's scope and would risk re-triggering the spec gate inappropriately. The validate skill itself does not re-check spec status.
