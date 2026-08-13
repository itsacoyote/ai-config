---
name: writing-skills
description: Use when creating, editing, porting, or validating portable Agent Skills for Codex or Pi, especially when SKILL.md discovery, structure, resources, or behavior needs review.
---

# Writing Skills

## Overview

Treat skill authoring as test-driven development for process documentation: observe how an
agent behaves without the skill, write the smallest guidance that changes that behavior,
then test again and close the loopholes the agent actually finds.

**Core principle:** If you did not observe the baseline behavior, you do not know whether
the skill teaches the right thing.

Codex and Pi both discover repository skills under `.agents/skills/` and personal skills
under `~/.agents/skills/`. This library ships portable copies under `agents/skills/`; keep
every shared skill self-contained inside that tree.

## When to create a skill

Create a skill when guidance is reusable, depends on judgment, and should be available
across tasks. Good candidates include:

- a technique that is easy to apply incorrectly;
- a repeatable workflow with meaningful decisions;
- a durable pattern future agent sessions should recognize;
- a reference needing task-specific retrieval or application guidance.

Do not create a skill for:

- a one-off solution;
- a project convention that belongs in `AGENTS.md`;
- a mechanical rule better enforced by a formatter, linter, or script;
- generic knowledge the target agent already has and can verify from current primary docs.

## Porting a skill across harnesses

A port is a semantic rewrite, not a search-and-replace exercise.

1. Inventory the source `SKILL.md`, references, scripts, assets, and dependencies.
2. Separate durable methodology from source-harness mechanics.
3. Re-derive discovery, invocation, tools, paths, permissions, and delegation for each
   target harness from current primary documentation.
4. Inline required guidance that will not travel with the target tree; otherwise bundle it.
5. Remove source-harness terminology, paths, commands, metadata, and stale examples.
6. Run a RED baseline before writing the port, then run the same scenarios with the port.
7. Validate the complete target directory, links, and bundled scripts.

Do not preserve a source file merely because it exists. Keep it only when it still teaches
or enables something the target skill needs.

## RED → GREEN → REFACTOR

### RED: establish the baseline

Before writing or editing behavioral guidance:

1. Create representative prompts that make the missing behavior matter.
2. Run them in fresh isolated agents or clean sessions without the new skill.
3. Capture the exact choices, omissions, and rationalizations.
4. Identify the smallest set of failures the skill must correct.

For a pure reference skill, RED can be a retrieval or application failure rather than a
discipline violation. The requirement is evidence of a gap, not artificial pressure.

### GREEN: write the minimum effective skill

Write only enough guidance and resources to address observed failures. Re-run the same
prompts in fresh isolated agents or clean sessions that receive the skill path and are told
to read it completely.

The skill is GREEN when agents consistently produce the expected behavior and can find the
resources they need without unrelated context.

### REFACTOR: close observed gaps

When an agent finds a new loophole or misses a resource:

- capture the failure verbatim;
- improve the trigger, instruction, example, or file routing that caused it;
- remove content that did not influence behavior;
- re-run the affected baseline/with-skill pair.

Read [testing skills with isolated agents](references/testing-with-isolated-agents.md) before
designing or running a full evaluation campaign.

## Open Agent Skills structure

Use the standard directory layout:

```text
skill-name/
├── SKILL.md              # required metadata and instructions
├── scripts/              # optional executable helpers
├── references/           # optional documentation loaded on demand
├── assets/               # optional templates and static resources
└── agents/
    └── openai.yaml       # optional OpenAI client extension
```

`agents/openai.yaml` is not part of the base Open Agent Skills specification. Add it only
when the skill needs Codex UI metadata, invocation policy, or tool dependencies.

### Frontmatter contract

`SKILL.md` starts with YAML frontmatter followed by Markdown instructions.

| Field | Requirement |
|---|---|
| `name` | Required; 1–64 lowercase letters, numbers, or hyphens; no leading, trailing, or consecutive hyphens; must match the directory name |
| `description` | Required; 1–1024 characters; enough capability and trigger language for discovery |
| `license` | Optional; license name or bundled license reference |
| `compatibility` | Optional; 1–500 characters describing real environment requirements |
| `metadata` | Optional; string keys mapped to string values |
| `allowed-tools` | Optional and experimental; support varies by client |

Use lowercase names in examples; uppercase display names are not valid identifiers:

```markdown
---
name: condition-based-waiting
description: Use when tests depend on timing, race intermittently, or rely on fixed sleeps.
---
```

Do not impose a 1024-character limit on the entire frontmatter block. That limit belongs to
the `description` field.

## Shared discovery and invocation

Codex and Pi both support the standard personal and repository locations. Invocation differs:

| Capability | Codex | Pi |
|---|---|---|
| Repository | `.agents/skills/<name>/` from the working directory toward the repository root | `.agents/skills/<name>/` from the working directory toward the repository root |
| Personal | `~/.agents/skills/<name>/` | `~/.agents/skills/<name>/` |
| Explicit | Mention `$skill-name` or select through `/skills` | Invoke `/skill:name` |
| Implicit | Description matches the task | Description matches the task |

Both harnesses also have native locations or extensions beyond this portable library. Keep
shared installation guidance on `.agents/skills` and `~/.agents/skills`; document a native
location only when a skill intentionally targets one harness. Read
[Agent Skills authoring across harnesses](references/agent-skills-authoring.md) before
depending on client-specific behavior.

### Write descriptions for discovery

This repository uses a stricter trigger-led convention than the base specification:

- start with `Use when...`;
- describe concrete situations, symptoms, file types, tools, or user intents;
- front-load the most important trigger words because clients may shorten descriptions when
  many skills are installed;
- keep workflow steps out of the description so metadata does not become a shortcut around
  reading the body;
- state adjacent non-triggers when scope could be confused with another skill.

The name plus trigger-led description still communicates what the skill covers while
keeping selection precise.

```yaml
# Bad: vague
description: Helps write docs.

# Bad: substitutes a workflow summary for trigger conditions
description: Use for skill TDD by running a baseline, writing instructions, and retesting.

# Good: concrete trigger conditions
description: Use when creating, editing, porting, or validating portable Agent Skills.
```

Use keywords an agent encounters in the actual task: relevant errors, symptoms, commands,
libraries, formats, and common synonyms. Avoid keyword stuffing that broadens the skill
beyond its real job.

## Progressive disclosure

Keep `SKILL.md` focused on routing and the core workflow. Open Agent Skills recommends
fewer than 500 lines and roughly 5,000 tokens for the main instructions.

Move out long references, domain-specific detail needed only for some tasks, reusable
executable helpers, and templates or static inputs. Keep references one level deep from
`SKILL.md`, and tell the agent exactly when to read each file. For references longer than
100 lines, add a short contents list. For scripts, state whether to execute or read them.

## Writing effective instructions

### Match precision to risk

| Situation | Instruction style |
|---|---|
| Several approaches are valid | Explain goals and decision heuristics |
| A preferred pattern allows variation | Give ordered steps or parameterized pseudocode |
| The operation is fragile or consistency-critical | Provide an exact script or command plus validation |

Explain why a constraint matters. Use absolute language only for genuine hard boundaries,
safety rules, or loopholes observed during RED/REFACTOR testing.

### Prefer one strong example

Choose a realistic example that demonstrates the hard part. It should be complete enough to
adapt without turning a general skill into a one-case template. Avoid repeating the same
example in multiple languages.

### Cross-reference without duplication

Name another skill and mark whether it is required or related. Do not copy its methodology
into the current skill, and do not embed absolute installation paths.

```markdown
**Required skill:** Use `writing-tests` before changing behavior covered by tests.
```

### Build feedback loops

For quality-critical output:

1. produce a draft or intermediate artifact;
2. run the validator or compare against the checklist;
3. fix concrete failures;
4. repeat until the check passes;
5. verify the final output, not only the intermediate form.

## Mechanical validation

Run the bundled lightweight validator from the repository root:

```sh
agents/skills/writing-skills/scripts/check-skill.sh \
  agents/skills/<skill-name>

agents/skills/writing-skills/scripts/check-skill.sh --all
```

It checks deterministic conventions used by this shared tree: required frontmatter,
identifier rules, directory/name agreement, field lengths, trigger-led descriptions, and
relative links. It supports plain single-line frontmatter values rather than claiming to be
a complete YAML parser.

After changing the validator, run its self-contained regression suite:

```sh
bash agents/skills/writing-skills/scripts/tests/check-skill-test.sh
```

When `skills-ref` is already available, also run:

```sh
skills-ref validate agents/skills/<skill-name>
```

Do not install validation tooling or access the network without user authorization.

## Common mistakes

| Mistake | Correction |
|---|---|
| Mechanically replacing vendor names | Re-derive each target's paths, tools, permissions, invocation, and delegation |
| Writing before RED | Run a fresh baseline and capture actual failures first |
| Description summarizes the workflow | Describe concrete trigger conditions instead |
| Main file contains every detail | Route optional detail through direct references |
| Reference chain is multiple levels deep | Link every required resource directly from `SKILL.md` |
| Script leaves errors for the agent to guess | Return specific, actionable errors and non-zero status |
| Shared skill depends on files outside `agents/skills/` | Inline or bundle every required dependency |
| Testing only happy paths | Include near-miss triggers, edge cases, and pressure where relevant |

## Completion checklist

Track these items with the current harness's plan mechanism for any non-trivial skill change.

### RED

- [ ] Representative scenarios defined, including near-miss non-triggers
- [ ] Fresh baseline runs completed without the new skill
- [ ] Failures, omissions, and rationalizations captured

### GREEN

- [ ] Target directory and `name` match
- [ ] Frontmatter follows Open Agent Skills constraints
- [ ] Description is trigger-led and specific
- [ ] Main instructions are focused and under 500 lines
- [ ] Supporting files use standard directories and direct links
- [ ] Target-harness mechanics replace source-harness assumptions
- [ ] Same scenarios pass with the skill loaded

### REFACTOR AND VERIFY

- [ ] New loopholes or navigation failures addressed
- [ ] Unused or duplicated content removed
- [ ] Bundled scripts exercised on success and failure cases
- [ ] `check-skill.sh` passes for the skill and shared tree
- [ ] `skills-ref validate` passes when the tool is available
- [ ] No dead links or stale harness terminology remain
- [ ] README or architecture decisions updated when discovery or capabilities changed

## References

- Read [Agent Skills authoring across harnesses](references/agent-skills-authoring.md) when a
  platform behavior, location, metadata field, or portability decision affects the skill.
- Read [testing skills with isolated agents](references/testing-with-isolated-agents.md) before
  designing evaluations or changing discipline-enforcing guidance.
- Read [persuasion principles](references/persuasion-principles.md) only when a skill must
  resist rationalization under pressure; ordinary reference skills need clarity, not force.
