# AI Config

A reusable development workflow for AI coding agents.

This project gives Claude Code, Codex, and Pi a shared way to take meaningful software work from an idea to a reviewed, documented change:

```text
Define → Research → Plan → Plan Review → Implement → Validate → Document
```

It combines workflow guidance, engineering practices, specialist knowledge, and independent review roles into a library you can bring into other projects.

## What you get

- **A deliberate feature workflow** — clarify the problem before coding, study the existing system, make an explicit plan, implement incrementally, validate independently, and document the result.
- **Reusable engineering judgment** — guidance for testing, security, API design, frontend work, databases, browser testing, git, CI/CD, migrations, and documentation.
- **Independent review** — focused reviewer roles for engineering quality, security, design, test coverage, plans, and pull requests.
- **Human control** — the workflow is manual by default, with approval gates before implementation and before a pull request is finalized.
- **Durable project memory** — features, tasks, findings, and handoffs are tracked in [beads](https://github.com/gastownhall/beads), rather than disappearing into chat history.
- **Cross-agent portability** — the same methodology is available to Claude Code, Codex, and Pi, with adaptations where their capabilities differ.

## Why this exists

AI coding tools are good at producing code, but useful software work needs more than code generation. Requirements can be vague, existing patterns can be missed, reviews can rubber-stamp the work that produced them, and important context can vanish between sessions.

This library is designed to make those failure modes less likely. Its core intentions are:

1. **Understand before changing.** Research the codebase, define success, and independently review the plan before implementation.
2. **Make work inspectable.** Record decisions, tasks, evidence, and unresolved risks outside the conversation.
3. **Separate creation from evaluation.** Use fresh, focused contexts for research and review.
4. **Match rigor to the work.** Use the full workflow for meaningful features without forcing ceremony onto trivial changes.
5. **Keep the human in charge.** Automation may coordinate work, but it does not remove approval and review gates.
6. **Share methodology without pretending tools are identical.** Preserve one set of engineering ideas while being explicit about harness-specific limits.

## Who it is for

This repository is useful if you:

- work with AI coding agents across multiple projects;
- want a repeatable path from feature idea to reviewable pull request;
- care about codebase research, incremental implementation, and independent validation;
- want workflow state to survive context resets and agent changes; or
- maintain agent instructions as a tested, versioned library rather than a collection of prompts.

It is intentionally opinionated. The complete feature workflow requires beads, uses Conventional Commits, and favors explicit checkpoints over fully autonomous coding.

## Explore the library

- **[Skill catalog](.agents/catalog.md)** — browse the available workflow, research, engineering, review, design, and maintenance skills.
- **[Technical guide](docs/technical-guide.md)** — installation, repository structure, harness differences, permissions, invocation, validation, and maintenance.
- **[Architecture decision](docs/decisions/0003-agent-agnostic-library.md)** — why Claude and the portable agent library currently live side by side.
- **[Contributor guidance](CLAUDE.md)** — conventions for maintaining this repository.

## Project status

Claude Code, Codex, and Pi have been smoke-tested against representative workflows. The existing Claude configuration remains supported while the portable library develops alongside it. Neither implementation is treated as the canonical source until longer-term parity is proven.

Browser integrations and isolation capabilities vary by agent. The technical guide documents those differences rather than claiming identical behavior everywhere.
