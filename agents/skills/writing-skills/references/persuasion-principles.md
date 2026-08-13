# Persuasion Principles for Skill Design

Use this reference only when a skill enforces a costly boundary that agents predictably
rationalize away. Ordinary technique and reference skills should rely on clarity.

## Purpose

Bright-line language can reduce decision fatigue and close loopholes under pressure. Use it
to protect the user's genuine interests, not to manufacture urgency or suppress judgment.

## Principles

### Authority

Use direct, non-negotiable language for established safety or correctness boundaries.

```markdown
Write code before the required failing test? Remove it and restart from the test.
```

Avoid authority language when several approaches are valid.

### Commitment

Make the next action observable: announce the skill, choose among concrete options, or track
a checklist in the current plan mechanism. This prevents a rule from becoming passive
background reading.

### Immediacy

Place validation directly after the action it checks. “Validate before proceeding” is more
effective than “validate later” because it removes the gap where work accumulates on a bad
foundation.

### Social proof

State a real universal convention when one exists. Do not invent consensus or consequences.

### Unity

Frame collaborative practices around shared outcomes: reliable software, honest technical
judgment, and changes the team can maintain.

## Combinations by skill type

| Skill type | Useful approach | Avoid |
|---|---|---|
| Discipline | Authority + commitment + explicit loophole counters | Guilt, false urgency, popularity claims |
| Safety-critical | Exact boundary + immediate verification | Escape hatches without a defined escalation |
| Technique | Moderate direction + explanation | Heavy-handed absolutes |
| Collaborative | Shared goal + observable handoff | Sycophancy |
| Reference | Clarity only | Persuasion framing |

## Ethical test

Before strengthening language, ask:

1. What behavior must change?
2. What observed rationalization defeats the current wording?
3. Is the boundary genuinely fixed, or does context require judgment?
4. Would the technique still serve the user if they understood exactly how it works?
5. Can a validator or permission boundary enforce this more reliably than prose?

If the answer to the fourth question is no, do not use the technique.

## Research foundation

- Cialdini, R. B. (2021), *Influence: The Psychology of Persuasion*.
- Meincke et al. (2025), *Call Me A Jerk: Persuading AI to Comply with Objectionable
  Requests*.

These sources motivate testing instruction compliance under pressure; they do not justify
false claims, coercion, or bypassing user authority.
