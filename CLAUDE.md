# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commits and PRs

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages and PR titles: `type(scope): description`. No `Co-Authored-By` trailers.

## Docs Directory

This project uses a @docs/ directory for persistent context.

```text
.docs/
└── YYYY-MM-DD-<short-name>/        # Folder for a feature
  ├── artifacts/
    └── <artifacts>                 # Artifacts and resources for feature
  ├── output-artifacts/
    └── <implementation artifacts>  # Artifacts from implementation, like screenshots or recordings
  ├── 1_spec.md                     # Define step that outlines the specs, scope, constraints, validation etc
  ├── 2_research.md                 # Results of studying and identifying areas of code and domain
                                      to be affected by the feature
  ├── 3_plan.md                     # Step by step implementation details broken down into tasks
  └── 4_validate.md                 # Validation of implementation. QA, testing, revisions, etc
```
