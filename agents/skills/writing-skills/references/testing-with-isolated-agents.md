# Testing Skills With Isolated Agents

Use this reference before deploying a new skill or changing guidance that should alter agent
behavior. Isolation matters because an evaluation is only useful when the test agent cannot
borrow the author's reasoning, hidden context, or earlier attempts.

## Contents

- Choose the evaluation type
- RED: capture the baseline
- GREEN: test with the skill
- REFACTOR: close observed gaps
- Test triggering separately
- Record and compare results

## Choose the evaluation type

Match the test to the claim the skill makes:

| Skill type | What the evaluation must show |
|---|---|
| Discipline | The agent follows the rule under realistic pressure and does not rationalize around it |
| Technique | The agent applies the method correctly to representative and edge cases |
| Pattern | The agent recognizes when the pattern fits and when it does not |
| Reference | The agent retrieves and applies the right facts without loading unrelated material |
| Port | The agent uses the target harness's paths, tools, invocation, permissions, and delegation correctly |

If a skill claims portability, run the relevant tests in every claimed target. A Codex-only
pass does not establish Pi compatibility, and a Pi-only pass does not establish Codex
compatibility.

## RED: capture the baseline

Create a small prompt set before editing the skill:

1. A representative task where the skill should trigger.
2. An edge case that stresses the hardest decision or constraint.
3. A near-miss where the skill should not trigger or should defer to another skill.
4. For discipline skills, a realistic pressure scenario that makes the wrong shortcut
   attractive.

Run each prompt without the new or edited skill. Use an isolated agent or a clean session;
do not fork the full authoring conversation into the evaluator.

- In Codex, use the available isolated-agent or subagent workflow when the environment
  provides one.
- In Pi, use the current isolated-agent mechanism or configured extension when available.
- If the harness has no isolation capability, open a separate clean session with only the
  task files and prompt. Label this as a degraded fallback in the test record.

Keep the shared worktree read-only for evaluators unless the scenario specifically tests
edits. Put disposable artifacts in a temporary workspace so concurrent evaluations cannot
overwrite the skill or each other's results.

Capture exact outputs and note:

- the path the agent chose;
- tools or commands it attempted;
- missing steps and incorrect assumptions;
- rationalizations for ignoring a constraint;
- whether it selected the skill at all.

The RED result is evidence of the gap. Do not rewrite a passing baseline into a failure just
to justify more guidance.

## GREEN: test with the skill

Run the same prompts in fresh isolated agents or clean sessions. Give each evaluator the
skill path and require it to read `SKILL.md` completely. Do not add coaching that reveals
the expected answer.

For a portable skill, compare target-specific mechanics explicitly:

- correct personal and repository discovery paths;
- correct explicit invocation syntax;
- available tools and permission boundaries;
- supported isolation or delegation mechanism;
- behavior when an optional client extension is absent.

GREEN means the skill changes the observed behavior consistently without needing hidden
author context. One lucky run is weak evidence; repeat judgment-heavy or pressure-sensitive
scenarios enough to expose inconsistent behavior.

## REFACTOR: close observed gaps

For every failure:

1. Quote or summarize the concrete failure in the test record.
2. Identify whether the cause is the trigger, instruction, example, resource routing, or a
   client-specific assumption.
3. Make the smallest change that addresses that cause.
4. Re-run the failing baseline/with-skill pair.
5. Re-run nearby passing cases to ensure the fix did not broaden the skill incorrectly.

Remove guidance that does not affect results. Long instructions are not automatically more
reliable; they can hide the decision that matters.

## Test triggering separately

Behavior tests that force-load a skill do not prove discovery works. Test selection with
ordinary task prompts too:

- positive prompts using the words users naturally use;
- paraphrases that omit the skill name;
- near-miss prompts for adjacent skills;
- explicit invocation in each claimed harness.

For Codex, verify description matching and the supported `$skill-name` or `/skills` path.
For Pi, verify description matching and `/skill:name`. Treat current client diagnostics as
supporting evidence, not a substitute for observing actual selection.

## Record and compare results

A useful test record includes:

```text
Harness and version:
Isolation mechanism:
Skill revision:
Prompt:
Expected behavior:
Baseline result:
With-skill result:
Observed gap:
Follow-up change:
```

The evaluation is complete when:

- representative, edge, and near-miss cases have baseline and with-skill results;
- every claimed target harness has been exercised, or an untested claim has been removed;
- failures are fixed and re-run;
- clean-session fallbacks are clearly labeled where true isolation was unavailable;
- mechanical validation passes after the final behavioral edit.
