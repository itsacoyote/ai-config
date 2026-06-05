---
name: onboard
description: Use when joining or returning to an unfamiliar codebase and you need a thorough, plain-language orientation — what it is, the stack, how to set up/run/test, the architecture, the conventions, and why key decisions were made — before you start working in it.
argument-hint: "[focus area]"
---

# Onboard

Give a newcomer (or a returner) their first thorough walkthrough of a whole project, in the main session, in plain language — assume no prior context and explain things concretely. Explore systematically, surface not just *what* the architecture is but *why* (from the project's ADRs), present a structured orientation, then stay in conversation to answer follow-ups with the context you just loaded.

A focus-area argument (`/onboard billing`) scopes both the exploration and the output to that one subsystem.

**This is read-only.** The only file you may ever write is the opt-in `ONBOARDING.md` (see [Doc artifact](#doc-artifact)) — and only after the user explicitly confirms. Never edit, create, or delete any other project file; no git writes, no installs, no "tidying up." If you notice something worth changing, mention it in the orientation instead.

## When NOT to use

- A repo you already know well, or one trivial enough to grasp at a glance — say onboarding isn't needed rather than over-exploring.
- Feature-scoped study of the codebase → use `research`.
- Understanding a single file or module → use `analyze-code`.
- A recap of recent work / a standup briefing → use `standup`.

## Systematic exploration

Read broadly first, then dive where it matters. Work roughly in this order; let what you find redirect you. Detect the stack from what's actually in the repo — **don't assume Node** (or any one ecosystem).

1. **Project docs** — README, `CLAUDE.md` (and any agent/contributor guides), and a `docs/` directory. The fastest source of intent.
2. **Manifests + lockfiles** — the stack, scripts, and dependencies. Look across ecosystems: `package.json`/lockfile, `pyproject.toml`/`requirements.txt`, `go.mod`, `Cargo.toml`, `Gemfile`, `pom.xml`/`build.gradle`, `composer.json`, etc. The lockfile tells you the package manager.
3. **Config + `.env.example`** — what the project needs to run: required env vars, services, feature flags, config files.
4. **Structure & key directories** — survey the tree (e.g. `find . -type f` excluding `node_modules`, `.git`, `dist`, `build`, vendored deps), then name the key directories and what each owns.
5. **Entry points** — where execution starts (`main.*`, `index.*`, `app.*`, `server.*`, CLI bins, route roots). Use `analyze-code` on the entry points and core modules rather than re-deriving that methodology here.
6. **Trace one complete end-to-end flow** — follow a single user-facing action from entry to output (e.g. request → route → service → store → response). This is the fastest way to see how the pieces actually connect.
7. **ADRs** — find and read the project's architecture decision records ([ADR sweep](#adr-sweep)), and fold their decisions + rationale into the orientation.
8. **Run / test commands + setup** — the exact setup steps, the exact run command (and what "working" looks like), and the exact test command(s) and types available. Read them from the project's scripts/docs — concrete commands, not assumed ones.
9. **Recent git history** — `git log --oneline -20` for what's been worked on, `git log --oneline --stat -5` for what's actively changing. Note in-progress work, migrations, and rough edges. (Read-only `git log` only — no writes.)

Use `find-patterns` for the codebase's conventions (naming, structure, state, error handling) instead of restating that methodology here.

### ADR sweep

Search the common locations, then match by convention:

- **Locations:** `docs/adr/`, `docs/architecture/decisions/`, `doc/adr/`, `adr/`, `decisions/` (and `docs/decisions/`).
- **Conventions:** files named `NNNN-title.md`, or files whose content carries `Status:` / `Context` / `Decision` / `Consequences` headings, or the phrase "Architecture Decision Record."

For ADR structure and conventions, defer to the `documentation-and-adrs` skill — don't restate them here.

For each ADR found, capture the decision and its rationale (the *why*, the constraints, the alternatives weighed). Fold these into the orientation — they also feed the **key concepts** and **conventions** sections. **If no ADRs exist, say so plainly** — never fabricate one or infer a "decision record" that isn't written down.

## The orientation

Present a structured, plain-language walkthrough in the session. Be concrete — name exact paths and commands, show examples instead of abstracting. **Scale it to the project**: a small repo gets a tight version; collapse or drop sections that genuinely don't apply rather than padding. When a focus area was given, scope every section to that subsystem.

Cover these sections:

- **What is this** — one paragraph: what it does, the problem it solves, who uses it.
- **Tech stack** — language, framework, storage, and only the dependencies that shape how you work.
- **Setup** — exact step-by-step to get it running locally.
- **Run** — the exact command to start it, and what you should see when it's working.
- **Test** — the exact test command(s); which types exist (unit/integration/e2e).
- **Architecture** — how the system is structured; main layers/components and how they relate (a list or simple diagram beats a paragraph).
- **Key directories** — a table of important paths and what each owns.
- **Entry points** — where the code starts; the files a developer touches most.
- **Data flow** — the one end-to-end flow you traced, walked through step by step.
- **Key concepts** — domain knowledge and non-obvious patterns needed before changing anything (ADR decisions inform this).
- **Conventions** — naming, structure, state, and error-handling patterns that keep the code consistent (from `find-patterns`).
- **Decisions & rationale (from ADRs)** — the significant decisions and *why* they were made, from the ADR sweep. If there are none, state that no ADRs were found.
- **Recent activity** — what's been worked on lately; active migrations or in-progress work.
- **Things to investigate** — open questions and anything that wasn't clear.

### Degrade gracefully

If something can't be determined — sparse repo, unfamiliar stack, no test command, no ADRs — **name what you couldn't determine and flag it under "things to investigate."** Do your best with what's there; **never fabricate** commands, architecture, or ADRs to fill a gap.

## Doc artifact

Present the walkthrough **in-session by default.** Then offer to save it as `ONBOARDING.md` (a visible file) in the project root.

- Write `ONBOARDING.md` **only after the user explicitly confirms.** Use the same sections as the orientation, with a title and date at the top.
- If the user declines, **write nothing.**
- **Never write any other file** — not `CLAUDE.md`, not the README, not a dotfile — unless the user explicitly asks during the conversation.

## Stay in conversation

After presenting, invite questions. You now hold the full context you just loaded — use it. Answer follow-ups specifically, with file paths and concrete examples. Stay available as long as the user has questions; don't hand off to another skill.
