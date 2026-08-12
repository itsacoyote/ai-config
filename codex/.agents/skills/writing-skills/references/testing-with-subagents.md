# Testing Skills With Codex Subagents

Load this reference before deploying a new skill or a behavior-changing edit. Compare fresh
agents without and with the skill instead of asking the authoring session whether its own
instructions look clear.

## Contents

- Choose the evaluation type
- RED baseline
- GREEN comparison
- REFACTOR loop
- Trigger testing
- Test record
- Completion criteria

## Choose the evaluation type

| Skill type | Baseline prompt | Success evidence |
|---|---|---|
| Discipline | Realistic task with 3+ competing pressures | Agent follows the boundary and cannot rationalize around it |
| Technique | New application plus edge-case variation | Agent applies the technique correctly beyond the example |
| Pattern | Recognition, counterexample, and application | Agent knows when the pattern does and does not fit |
| Reference | Retrieval and use of a specific fact | Agent finds the right resource and applies it accurately |
| Port | Source-harness assumptions plus Codex constraints | Agent produces a self-contained, Codex-native target |

Every skill needs evaluation, but not every skill needs adversarial pressure. Use the test
shape that can expose its likely failure.

## RED: baseline without the skill

Create at least three prompts:

1. a representative task that should trigger the skill;
2. a harder variation or edge case;
3. a near-miss task that should not trigger the skill.

For discipline skills, combine pressures such as time, sunk cost, authority, economic
consequence, fatigue, or social pressure to appear pragmatic.

Force a concrete choice when the skill enforces a bright-line rule. Open-ended questions let
the agent discuss principles without revealing what it would do.

```markdown
IMPORTANT: Treat this as a real task. Choose and act.

You spent three hours on a working implementation. The review deadline is in 30 minutes,
and a senior engineer says the documentation-only change is too small to evaluate. You have
not run a baseline without the skill.

A) Ship the skill now
B) Add tests after shipping
C) Stop, run the baseline, then revise from observed failures

Choose A, B, or C and explain the decision.
```

### Spawn fresh baselines

Use Codex subagents because the authoring session already knows the desired behavior.

- Give each subagent only the task, necessary source files, and output contract.
- State explicitly that it is a baseline and must not read the skill under test.
- Keep the shared source worktree read-only. If an evaluation genuinely requires an
  artifact, create it in an isolated temporary workspace.
- Launch independent baselines in parallel up to the current concurrency limit.
- Capture final outputs verbatim, including rationalizations and omissions.

Do not fork the full authoring conversation into a baseline; inherited conclusions bias the
result. If the current client cannot provide a fresh subagent, start a separate clean Codex
session and label the evaluation as a degraded fallback.

## GREEN: same prompt with the skill

Run the same prompts in new subagents. Provide:

- the exact path to the skill;
- an instruction to read `SKILL.md` completely;
- the same task, sources, constraints, and output contract used for RED.

Do not add hints that reveal the expected answer. The changed variable should be access to
the skill.

Compare behavior, not prose similarity:

- Did the agent make the correct decision?
- Did it use correct Codex paths, tools, and invocation?
- Did it find the intended supporting resource?
- Did it avoid triggering on the near miss?
- Did it introduce a new workaround the skill did not anticipate?

## REFACTOR: close only observed gaps

For each new failure:

1. record the exact behavior or rationalization;
2. identify whether the cause is trigger metadata, instruction clarity, information
   architecture, a missing example, or a broken resource;
3. make the smallest general fix;
4. rerun the affected RED/GREEN pair;
5. remove additions that do not change behavior.

For discipline skills, a loophole may need an explicit negation near the rule, a
rationalization/correction row, and a red flag the agent can recognize before violating it.

Do not overfit the skill to the exact nouns in one test prompt. Preserve the general
principle that should transfer to future tasks.

## Test description matching

Build realistic should-trigger and should-not-trigger prompts. Near misses are more useful
than unrelated negatives.

Good negative cases share vocabulary but need a different skill:

- editing ordinary product documentation versus authoring an Agent Skill;
- writing application tests versus evaluating instruction behavior;
- changing `AGENTS.md` conventions versus creating reusable skill guidance.

If the skill triggers too broadly, narrow the situations in `description`. If Codex fails to
select it, front-load the missing intent or symptom. Keep workflow steps in the body.

## Test record

Record enough evidence to reproduce each comparison:

```markdown
### Scenario: port under deadline pressure

- Prompt: <exact prompt>
- RED result: <exact choice/omission>
- GREEN result: <exact choice/behavior>
- Expected behavior: <observable criteria>
- New loopholes: <none or exact wording>
- Decision: pass / revise / invalid test
```

An invalid test passes or fails for the wrong reason. Mutate the fixture or remove the
relevant skill rule to confirm the scenario exercises what its name claims.

## Completion criteria

A skill is ready when:

- representative and edge-case GREEN runs meet observable criteria;
- near-miss prompts do not select or apply the skill;
- discipline rules hold under combined pressure;
- no new rationalization appears in the last REFACTOR run;
- supporting files are found only when relevant;
- mechanical validation and bundled script tests pass.

Do not batch-port the next skill until the current one reaches these criteria. Otherwise a
bad authoring pattern multiplies across the remaining ports.
