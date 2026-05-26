# Research: Fix validate agent to run and fix e2e tests before PR is ready for review

**Spec:** [1_spec.md](1_spec.md)
**Date:** 2026-05-26

## Summary

This research surveys the three files in scope (`.claude/agents/qa-reviewer.md`, `.claude/skills/validate/SKILL.md`, `.claude/agents/validate.md`) and the existing pipeline conventions they must mirror (the 3-attempt fix loop in `implement.md` / `validate.md` / `agent-context`, the conventional-commits + `Skill(git-commit)` pattern, and the push-failure escalation block). The change set is documentation-only: no new agents, no new skills, no code. Every requirement from the spec maps to specific paragraphs that already exist in these three files — what is missing is the e2e-execution gate. The patterns to mirror already exist verbatim inside the validate skill (Round 1's 3-attempt loop) and inside the implement agent (escalation `context.yaml` block, push-failure escalation, conventional commits, explicit `git add`). Adding e2e execution and fix-iteration is a structural addition to QA's review process plus tightening of the verdict contract; it is not a redesign.

## Codebase Areas Affected

- `.claude/agents/qa-reviewer.md` — needs the most invasive edit: e2e command detection, the run-tests-first directive, the 3-attempt fix loop with commits, the three-state verdict (Approved / Gaps / Escalated), and the post-green-only evidence capture.
- `.claude/skills/validate/SKILL.md` — Round 2 needs explicit e2e responsibility and green-suite gate language; the completion section needs an "e2e iterations + final result" entry.
- `.claude/agents/validate.md` — escalation block needs an e2e-failure variant; the `4_validate.md` template needs an "E2E Test Run" section.
- `.claude/agents/implement.md` — reference only. Provides the canonical push-failure escalation block, the explicit-path `git add` convention, and the `Skill(git-commit)` invocation order.
- `.claude/skills/feature/SKILL.md` — reference only. The orchestrator that reads `workflow.escalated` and halts on it; confirms what an escalating agent's `context.yaml` write needs to contain.
- `.claude/agents/senior-reviewer.md` — reference only. Confirms the spec's non-goal: senior review remains a code-and-design audit and does not own test execution.

## File-by-file analysis

### `.claude/agents/qa-reviewer.md` (80 lines)

**Current structure and instructions:**

- Frontmatter declares `model: sonnet`, skills `agent-context` + `verify-completeness`, and the `playwright` MCP server (already available — important, the agent can drive a browser if needed).
- "Review Process" has four sub-sections: Coverage audit, Unit test quality, Integration test quality, E2E test quality. Each tells the agent to read and inspect, never to run.
- "Evidence capture" (lines 48–61) opens with "Once all tests pass, capture visual evidence" — but nowhere is "all tests pass" verified. The agent is told to use Playwright/Cypress capture APIs.
- "Verdict" has only two states: gaps or "QA approved." There is no escalation state.
- "Non-negotiables" rejects coverage theater and mocked tests but says nothing about skipping tests or about running them.

**Changes required (mapped to spec):**

| Spec requirement | Where it lands |
|---|---|
| Run e2e suite as the first action (acceptance #1) | New section at top of "Review Process," before Coverage audit |
| Detect e2e command from project (req §QA Reviewer bullet 2) | Same new section; describe inspection order: `package.json` scripts, `Makefile`, README; if not found, record "no e2e framework configured" and skip running |
| 3-attempt fix-and-rerun loop (acceptance #2, req §QA Reviewer bullets 3–5) | New "E2E fix loop" subsection: diagnose → decide code-vs-test → fix → commit (`Skill(git-commit)` first, then `fix(<scope>): …` or `test(<scope>): …`) → re-run; cap at 3 |
| Record per-attempt log (req §QA Reviewer last bullet under fix loop) | Same subsection: state what to capture (failing tests, diagnosed cause, fix applied, re-run result) and where it flows (into the verdict, then into `4_validate.md`) |
| Three-state verdict — Approved / Gaps / Escalated (acceptance #3, req §QA Reviewer last sub-bullet) | Rewrite the "Verdict" section to enumerate exactly three states with explicit preconditions; Approved requires green HEAD + ≥ 80% coverage + no gaps |
| Prohibit skips / `.only` / `.skip` / `xtest` / `xit` / quarantining (acceptance #4, constraint) | Add to "Non-negotiables"; explicit list of forbidden patterns |
| Evidence capture only after green (acceptance #5) | Move evidence section to after the verdict-state definition or gate it with a one-line precondition referencing the green run |

### `.claude/skills/validate/SKILL.md` (60 lines)

**Current structure and instructions:**

- Header says this is the last gate; do not soften.
- Validation Loop is two rounds: Round 1 Senior Code Review, Round 2 QA Review. Each round has a 5-step fix iteration (fix → test → commit → re-invoke → repeat) capped at 3.
- Round 2 step 2 says "Run the full test suite and verify coverage stays above 80%" — this is the closest the skill comes to test execution, but it's a sanity check after QA's *fixes*, not a gate on QA's *approval*.
- Completion section enumerates four bullets in the summary: senior verdict + iterations, QA verdict + coverage + iterations, findings/fixes, evidence list.

**Changes required (mapped to spec):**

| Spec requirement | Where it lands |
|---|---|
| Round 2 documents e2e-execution responsibility (acceptance #6) | New paragraph at the top of "Round 2 — QA Review" stating QA's first action is running the e2e suite and entering the fix loop on failure |
| 3-attempt fix loop documented in skill (req §Validate skill bullet 1) | Same paragraph references the loop owned by the QA agent (do not duplicate the loop itself — the skill's existing 3-iteration Round 2 wrapper is separate and remains) |
| Green-suite gate (req §Validate skill bullet 2) | New paragraph after QA returns: if QA's verdict is "Approved" but the final state was not "all e2e tests passed on HEAD," treat it as a defect, re-invoke QA with the gap called out. This is a new conditional alongside the existing "if QA returns issues" branch |
| Completion summary includes e2e iteration count + final result (acceptance #7) | Add a bullet to the "Completion" list: "Number of e2e fix iterations and the final e2e result (green / escalated)" |

Note: the skill has *two* iteration concepts to keep straight:

1. The skill's own Round 2 fix-iteration cap of 3 (post-QA findings → fix → re-invoke).
2. The QA agent's internal e2e fix-iteration cap of 3 (failed test → diagnose → fix → re-run).

These are independent and both capped at 3. The skill orchestrates loop 1; the agent orchestrates loop 2. The skill should reference loop 2 by name but not redefine it.

### `.claude/agents/validate.md` (102 lines)

**Current structure and instructions:**

- Gate section: reads `context.yaml`, verifies branch, checks `3_plan.md`, confirms diff exists, reads spec/research/plan.
- Workflow section: delegates to `.claude/skills/validate/SKILL.md`.
- After workflow: writes `4_validate.md` using a fixed template, commits with conventional commits, pushes.
- Two escalation blocks: push-failure (lines 71–85) and "If the skill cannot complete" (lines 87–101). Both write `workflow.escalated: true` and `workflow.escalation_reason` to `context.yaml`.

**Changes required (mapped to spec):**

| Spec requirement | Where it lands |
|---|---|
| Escalation block extended for e2e-failure case (req §Validate agent bullet 1) | Either expand the existing "If the skill cannot complete" block or add a parallel "E2E failure escalation" block. The `escalation_reason` template must list: the failing tests, the 3 attempted fixes, the suspected root cause |
| `4_validate.md` template adds "E2E Test Run" section (acceptance #8, req §Validate agent bullet 2) | Modify the template embedded in lines 30–58 — insert a new section after "QA Review" listing: the final e2e command, the result, the number of fix iterations |

The push-failure escalation block (lines 71–85) requires no change: it already covers QA's pushes, since QA pushes through the same agent's terminal `git push`.

## Existing patterns the e2e loop must mirror

### Pattern: 3-attempt fix loop

Used in three places verbatim and always capped at 3. The e2e loop must adopt the same cap (spec constraint).

- **Validate skill, Round 1 & 2** (`.claude/skills/validate/SKILL.md:24-32, 41-51`) — the canonical text: "Repeat until the Senior Reviewer approves, up to a maximum of 3 fix iterations." Each round has a numbered 5-step recipe: fix → test → commit → re-invoke → repeat. When stuck after 3 attempts, return a summary of: unresolved findings / what was tried / root-cause assessment.
- **Implement skill, post-Code-Reviewer loop** (`.claude/skills/implement/SKILL.md:56`) — "the same issues after 3 fix attempts with no meaningful progress, stop." Same shape.
- **Agent-context contract** (`.claude/skills/agent-context/SKILL.md:95–103`) — defines the escalation contract for any agent that exhausts 3 attempts: write to `context.yaml`, do not notify the user.

What the e2e loop should look like, by direct analogy:

```
1. Diagnose failing test(s) — read output, find root cause.
2. Decide: is the bug in production code or in the test?
3. Apply the fix (no skip/quarantine).
4. Commit. Invoke Skill(git-commit) first. Conventional message:
   - fix(<scope>): … when the production code was wrong
   - test(<scope>): … when the test was wrong
5. Re-run the full e2e suite from a clean state.
Repeat up to 3 times. If still red after attempt 3, return Escalated verdict.
```

### Pattern: Escalation `context.yaml` block

The exact YAML block appears in every pipeline agent (`define.md`, `plan.md`, `implement.md`, `validate.md`, etc.). The shape is:

```yaml
workflow:
  escalated: true
  escalation_reason: |
    [What is failing and the exact error]
    [What was attempted in each of the 3 attempts and why it didn't work]
    [Assessment of why this is stuck]
```

The validate agent's existing "If the skill cannot complete" block (validate.md:87–101) is already this shape. For the e2e-failure case the spec asks for `escalation_reason` to list "the failing tests, the 3 attempted fixes, and the suspected root cause" — which is the same triple, just specialized. Either expand the existing block with an e2e-specific example or add a sibling block; the conservative choice is a sibling block so the existing skill-cannot-complete case stays unchanged.

The orchestrator (`feature/SKILL.md:60`) halts on `workflow.escalated == true` and announces `"Pipeline halted — " + workflow.escalation_reason`. The escalation chain is: QA returns Escalated verdict → validate skill surfaces it to validate agent → validate agent writes `workflow.escalated` → orchestrator halts. QA itself does not write to `context.yaml` — it returns its verdict to the skill, which returns to the agent, which writes the YAML. This separation must be preserved.

### Pattern: Push-failure escalation

Identical block in `define.md`, `plan.md`, `research.md`, `implement.md`, `validate.md`, `document.md`. The validate agent already has this at lines 71–85. No change needed for the e2e work.

### Pattern: Commit + push with conventional commits

Every agent follows the same recipe:

1. Invoke `Skill(git-commit)` first.
2. `git add <explicit paths>` — never `-A` or `.`.
3. `git commit -m "<type>(<scope>): <description>"`.
4. `git push`. On non-zero exit, write push-failure escalation and return.

QA's new fix commits inside the e2e loop must follow this recipe with no `Co-Authored-By` trailer (project `CLAUDE.md` + `git-commit` skill both enforce this). The natural commit types per the spec:

- `fix(<scope>): <description>` when the production code was wrong.
- `test(<scope>): <description>` when the test was wrong (assertion was incorrect, fixture was stale, selector broke).

QA's loop does not push between attempts — the validate agent does a single terminal push at the end of the Validate step that flushes every QA commit, exactly the way the implement agent flushes per-task commits in one terminal push (`implement.md:64`). This is the right precedent to follow: in-loop commits accumulate locally; one terminal `git push` flushes them.

### Pattern: Verdict states across reviewers

- **Senior Reviewer** (`senior-reviewer.md:36-49`): two terminal states — issues listed, or "Senior review approved." No escalation state at the reviewer level; the skill handles the 3-attempt cap.
- **QA Reviewer** (`qa-reviewer.md:65-75`): currently two terminal states — gaps listed, or "QA approved." This is what the spec changes — adding a third "Escalated" state.

The introduction of an Escalated verdict at the *reviewer* level (not just at the skill level) is a deliberate spec choice. It means the QA Reviewer agent itself becomes capable of signaling "I tried my own 3-attempt loop and couldn't get green," which is structurally different from the skill's own "I ran QA 3 times and gaps persist" loop. Both can fire; both end in the validate agent writing `workflow.escalated`.

### Pattern: Evidence-capture gate

Currently the qa-reviewer.md opens evidence capture with "Once all tests pass" but never *verifies* that condition. The fix is to make this an explicit gate: evidence capture only runs in the **Approved** verdict branch. Moving the evidence section under or after the verdict definition makes this structurally enforced rather than asserted.

## Architectural Context

- **Pipeline is strictly sequential.** Senior Review precedes QA Review precedes Document. The spec preserves this. The e2e loop sits inside QA Review, so it doesn't change the outer sequence.
- **Iteration caps are uniform at 3 throughout the pipeline.** Define, Plan, Implement (Code Reviewer loop), Validate (Senior loop, QA loop). The spec explicitly mandates 3 for the e2e loop too. Don't introduce a fourth number.
- **Escalation is one-shot.** Once an agent writes `workflow.escalated: true`, the orchestrator halts; resume requires the orchestrator to reset the flag and re-invoke the step. This is documented in `feature/SKILL.md:31`. Implication: QA's e2e Escalated verdict has the same recovery cost as any other escalation — the user must resume via `/feature` and the validate step re-runs from scratch.
- **MCP server access.** `qa-reviewer.md` already declares `playwright` MCP. This is the right tool for running and capturing e2e tests in projects that use Playwright. Other frameworks (Cypress, Vitest e2e, Jest e2e, native test runners) are run via Bash. The spec is framework-agnostic — detection comes from the project, not the agent.
- **What the agent can run.** The agent already has Bash access (transitively, via its skills). The validate agent allowed-tools list is `Read Bash(*) Agent`. The qa-reviewer's allowed-tools is not constrained in its frontmatter, so it inherits the broad default — Bash is available for `npm test`, `pnpm test:e2e`, `make e2e`, etc.

## Key Insights for the Planner

- **Three files, one logical change.** The work is a coordinated three-file edit. There is no code change. The Planner should produce one task per file plus a final integration-check task that verifies the three files reference each other consistently (the skill mentions the agent's loop, the agent's escalation block matches the skill's surfacing).
- **Two independent 3-attempt loops in QA.** Loop A (existing) is the skill's "QA returns gaps → fix → re-invoke QA → repeat" loop, capped at 3. Loop B (new) is the QA agent's internal "e2e fails → diagnose → fix → re-run → repeat" loop, also capped at 3. They compose: in the worst case, a QA invocation runs loop B (3 e2e attempts), returns gaps, the skill applies fixes from loop A, and re-invokes QA, which runs loop B again. Document this composition explicitly so it doesn't surprise the implementer.
- **Verdict-state vocabulary must match across files.** The QA agent emits "Approved / Gaps / Escalated"; the validate skill must consume those exact tokens; the validate agent's `4_validate.md` template must surface them. Keep the wording uniform — don't let the skill say "approved with green run" while the agent says "Approved." Use the three terms verbatim in all three files.
- **Evidence section relocation has a side effect.** Moving evidence capture to "after green only" means the qa-reviewer.md flow now has a clear early-exit on Gaps and on Escalated — no evidence is captured, `output_artifacts` is not populated. The validate agent's `4_validate.md` Evidence section must tolerate an empty `output_artifacts` list (it already does in template language: "List each entry from `output_artifacts`"). Confirm during implementation that no downstream agent (Document) assumes evidence exists.
- **No commits between QA's e2e fix attempts can be skipped.** The spec is unambiguous: each fix attempt commits. This serves two purposes — git history captures each diagnostic step, and rolling back a bad fix is `git revert` rather than re-editing. The Planner should preserve this; do not collapse the loop into "fix all three then commit once."
- **Detection logic must be cautious.** The agent inspects `package.json`, `Makefile`, README — and if nothing matches, records "no e2e framework configured" as a gap. It does **not** invent a command. This protects projects that have no e2e setup from being failed by a hallucinated `npm run e2e`. The Planner should call out unambiguous detection-precedence rules so the implementer doesn't have to guess.
- **Spec status is "Draft" in `1_spec.md`.** The orchestrator transitioned the workflow to research with `define` in `completed_steps`, so the gate effectively passed at the orchestrator level, but the spec file itself was not updated to `**Status:** Approved`. If the Plan or later steps re-check the gate strictly, this could halt them. The Planner should either flag a pre-flight task to update the status line or note that the approval is implicit from the orchestrator's state.

## Artifacts

None produced. The research is fully captured in this document; no diagrams, data samples, or external references were generated.

## Open Questions

- The spec calls for QA to detect the e2e command from `package.json` / `Makefile` / README. What is the precedence order if more than one is found (e.g., `package.json` has `test:e2e` and the Makefile has an `e2e` target)? Recommend: explicit `test:e2e` in `package.json` wins, then `Makefile` `e2e` target, then any script the README documents. The Plan step should lock the precedence so the implementer has one rule.
- Does the project running `/feature` always have npm/pnpm/yarn or another runtime available? If detection finds a `package.json` script but the runtime is missing, is that a "no e2e configured" gap or an escalation? Recommend: treat a missing runtime as a hard escalation because it indicates broken local setup, not absent configuration.
- The Validate skill says coverage must stay > 80% after QA fixes. If a QA e2e fix touches production code, coverage might drop. Should QA re-check coverage at the end of its e2e loop? Recommend: yes — coverage check is a Round 2 step regardless, but make it explicit that it runs *after* the e2e suite is green, not interleaved with the loop.
