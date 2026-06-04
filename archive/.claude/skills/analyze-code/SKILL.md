---
name: analyze-code
description: Survey a file, module, or area of the codebase to understand what it does and whether it's relevant to a feature under research. Use to quickly assess reusability and surface what the Planner needs to know.
argument-hint: "[file or directory path]"
allowed-tools: Read Bash(find *) Bash(grep *)
---

# Analyze Code

Survey `$ARGUMENTS` to understand what's there and how it relates to the feature being researched. If no target is provided, ask what to analyze.

## What to assess

**What it does** — what is this code responsible for? A one or two sentence summary is enough.

**Public interface** — what does it expose? Key exports, endpoints, component props, or function signatures that a caller would use.

**Direct dependencies** — what does it import or rely on? Stay one level deep — don't trace the full dependency tree.

**Reuse potential** — can this be used as-is, adapted with minor changes, or does it not fit the feature's needs?

## What to report

- What the code does (brief)
- What's exposed and usable
- Whether it's a reuse candidate, needs adaptation, or isn't relevant
- Anything that would directly affect the feature's implementation approach
