---
name: validate
description: Coordinate a senior code review followed by a QA review. Runs both reviewers in sequence, manages fix iterations between rounds, and produces a validation summary. Use after implementation is complete.
disable-model-invocation: true
allowed-tools: Read Bash(*) Agent
---

# Validate

Run a senior code review followed by a QA review. Fix issues and repeat until both reviewers pass.

If feature context (spec, plan, diff) isn't already in the conversation, ask the user to share what was implemented before beginning.

This is the last gate before code ships. Do not soften findings, rush approvals, or skip steps because the implementation looks mostly fine.

## Validation Loop

Run both reviewers in order. Do not advance to the next reviewer until the current one passes.

### Round 1 — Senior Code Review

Invoke the Senior Reviewer agent. Pass the spec, plan, and full diff as context.

If the Senior Reviewer returns issues:

1. Fix each issue exactly as specified — do not interpret or improvise on the fix.
2. Run the test suite after fixes to confirm nothing broke.
3. Commit the fixes.
4. Re-invoke the Senior Reviewer.
5. Repeat until the Senior Reviewer approves, up to a maximum of 3 fix iterations.

If the same issues persist after 3 attempts, stop. Return a clear summary of:
- Which issues remain unresolved
- What was attempted in each iteration and why it didn't work
- Your assessment of the root cause

Do not attempt further fixes.

### Round 2 — QA Review

QA's first action is to run the project's full e2e suite. On failure, QA enters its own 3-attempt fix-and-rerun loop, defined in `.claude/agents/qa-reviewer.md`. QA's internal e2e fix loop (cap 3) is independent of this skill's own Round 2 fix-iteration cap (also 3). Both apply; both are uniform across the pipeline.

Once the Senior Reviewer has approved, invoke the QA Reviewer agent.

If the QA Reviewer returns issues:

1. Fix each issue exactly as specified.
2. Run the full test suite and verify coverage stays above 80%.
3. Commit the fixes.
4. Re-invoke the QA Reviewer.
5. Repeat until the QA Reviewer approves, up to a maximum of 3 fix iterations.

If the same issues persist after 3 attempts, stop. Return a clear summary as above.

**Green-suite gate:** If QA returns the **Approved** verdict but the final state was not "all e2e tests passed on HEAD," treat the verdict as a defect. Re-invoke QA with the gap called out (e2e not actually run, or not actually green). This re-invocation counts against the same 3-iteration Round 2 cap.

## Completion

Once both reviewers have approved, produce a validation summary with:

- Senior review verdict and number of fix iterations
- QA review verdict, coverage achieved, and number of fix iterations
- Number of e2e fix iterations performed by the QA Reviewer and the final e2e result (green / escalated)
- For each finding that required fixing: what the finding was and what changed to resolve it
- A list of evidence artifacts captured by the QA Reviewer
