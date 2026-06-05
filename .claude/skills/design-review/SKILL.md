---
name: design-review
description: Use when reviewing a frontend/UI change — a diff that touches components, markup, styles, or templates — for component reuse, design-system correctness, component architecture, cross-component state/data flow, UX, and accessibility. Use during the Validate step or in pr-review as the frontend pass.
allowed-tools: Read Bash(git diff *) Bash(git log *) Bash(find *) Bash(grep *)
---

# Design Review

A frontend, UX, and accessibility review of a code change. You are the design-aware engineer on the team: you catch the component someone duplicated instead of reused, the raw hex that should be a token, the deep prop-drill, the missing empty state, and the keyboard trap — and you say exactly how to fix each one.

This is the **audit counterpart** to `frontend-ui-engineering` (which is the build standard). It does not restate those standards — it reviews against them. It is the frontend/UX/a11y half of the review lineup, alongside `senior-review` (engineering quality) and `qa-review` (test coverage). Distinguish it from `impeccable`, which *authors* design direction and visual craft — design-review audits against existing standards, it doesn't create them.

## When NOT to use

Non-frontend diffs. If the change touches only backend, CLI, config, or docs — no component/markup/style files — this skill no-ops gracefully (see Conditional engagement). Don't force a frontend lens onto a change that has no user-facing surface.

## Conditional engagement

Engage **only when the diff touches frontend** — component or markup or style files: `.tsx/.jsx/.vue/.svelte`, CSS/SCSS/Tailwind, and HTML/template files.

```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
git diff --name-only $(git merge-base HEAD ${BASE:-main}) HEAD \
  | grep -iE '\.(tsx|jsx|vue|svelte|css|scss|less|html|hbs|ejs|astro)$'
```

If nothing matches, **no-op**: report "No frontend changes — nothing to review" and stop. This is not a failure and **never blocks** — it's the correct outcome for a backend-only change.

## Scope

Review the change under review — by default the branch diff (the `git diff` between `git merge-base HEAD <base>` and `HEAD`), or a path/range the caller specifies. If a spec and plan exist (from `define` / `planning-and-task-breakdown`), review against them; if not (e.g. an external PR), review on frontend quality alone.

## Runtime vs. static mode

This skill supports **two modes**, and the **caller sets the default** — the skill does not decide:

- **`validate`** dispatches **runtime** by default — it's reviewing your own pre-ship code.
- **`pr-review`** dispatches **static** by default — never auto-run an untrusted PR's app; runtime is explicit opt-in only.

**Runtime mode** drives the running app via a browser MCP — the **Chrome DevTools MCP** (the `browser-testing-with-devtools` skill) preferred, falling back to **Playwright** when the Chrome MCP isn't configured — to evaluate what markup alone can't tell you: real focus order, computed contrast, breakpoint behavior, the accessibility tree, and interaction. Running the app and the browser is **evaluation, not a code change** — it stays within read-only.

> **Runtime needs capabilities beyond this skill's own `allowed-tools`** (which is scoped to read-only diff inspection). Starting the app and reaching the Chrome DevTools MCP come from the surface granted to the **`design-review` agent** — which is how `validate` dispatches it. Invoked **directly in-session** under the default tool set, this skill is **static-only**; run it through the agent for the runtime path.

**Graceful static fallback** — fall back to reviewing the diff and source statically, with no hard failure, when **any** of these hold:
- the app can't be run (no dev server, build fails, missing deps),
- no browser MCP is configured (neither the Chrome DevTools MCP nor Playwright),
- static-only was requested by the caller.

When you fall back, **say so** in the verdict ("reviewed statically; runtime checks not run because …") so the reader knows contrast/focus-order were not verified live. **Never block on the absence of runtime.**

## The six review areas

Run these as distinct, named areas — don't blur them into one shallow read. Each catches a different class of frontend problem.

### a. Component reuse & duplication

Use `find-patterns` to map the existing component inventory **before** judging the diff. Then flag:
- a new component that duplicates one that already exists (or near-duplicates it with trivial differences),
- a place that reinvents a pattern (modal, list, form field, empty state) the codebase already has a component for,
- copy-pasted markup/logic that should be one shared component.

### b. Tailwind / design-system correctness

Honor the project's design context — `DESIGN.md` and `PRODUCT.md` (and any token/theme files) are the source of truth; `frontend-ui-engineering` covers how. Flag:
- raw values (hex colors, arbitrary px) where a **semantic token** exists (`text-primary`, `bg-surface`, not `#3b82f6`),
- spacing off the project's scale (`p-[13px]`, `mt-[2.3rem]`),
- the **"AI aesthetic"** — purple/indigo defaults, excessive gradients, `rounded-2xl` everywhere, shadow-heavy layers, oversized uniform padding, stock card grids — where it drifts from the actual design system.

### c. Component architecture & interfaces

Review the structure and the props contract (lean on `api-and-interface-design` for interface design):
- composition over configuration (composable children, not a wall of boolean/variant props),
- focused components (one responsibility; oversized components split),
- props/interface design — minimal, well-typed, no leaked internals,
- **data/presentation separation** — data fetching in a container, rendering in a presentational component.

### d. State & data flow between components

Review where state lives and how it moves:
- right **state location** (local vs. lifted vs. context vs. URL vs. server vs. global) — see `frontend-ui-engineering`'s state table,
- **prop-drilling** deeper than ~3 levels that should be context or a restructure,
- **server vs. client state** kept distinct (don't hand-roll caching for what React Query/SWR owns; don't mirror server data into client state).

### e. UX

- **loading, empty, and error states** all present (no blank screens, no spinner where a skeleton belongs),
- **responsive** behavior across breakpoints (320 / 768 / 1024 / 1440),
- interaction patterns — focus moves on content change, optimistic updates where they help, no janky or surprising behavior.

### f. Accessibility — adaptive bar

Set the bar **adaptively**:
- If the project defines an a11y standard — a dedicated a11y doc, or an a11y section in `DESIGN.md` — review **against that**.
- Otherwise, review against **baseline WCAG 2.1 AA** using [`.claude/references/accessibility-checklist.md`](../../references/accessibility-checklist.md), and **note the absence** of a project standard in the verdict (an INFO-level finding — the project has no documented a11y bar).

Check keyboard navigation and focus management, ARIA/labels, contrast, and that color isn't the sole carrier of meaning. In **runtime mode**, verify focus order, computed contrast, and the accessibility tree against the live page rather than inferring from markup.

## Severity-gated verdict

Grade every finding with exactly one of `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` / `INFO` (the shared vocabulary — don't invent labels).

**Block on:**
- **accessibility violations** (against the adaptive bar),
- **component duplication / missed reuse**,
- **broken cross-component state or data flow** (wrong state location causing bugs, server data mirrored into client state going stale, prop-drilling that breaks on refactor).

**Advisory** (don't block): subjective visual polish, minor spacing/typography taste, "could be nicer" — flag as LOW/INFO so the author can choose.

**Output one of:**
- **"Design review approved"** — one or two sentences on what was reviewed and held up (note if it was static-only).
- An **ordered findings list** (blockers first), each with:
  - **Severity** — one of the five labels
  - **Where** — file, component, line if determinable
  - **What** — the precise problem
  - **Fix** — exactly what to change, not a vague suggestion

Record findings per the dual-mode contract in [`.claude/references/beads.md`](../../references/beads.md): standalone, present them in the session; beads-enhanced, file an issue per unresolved finding linked to the feature epic/task.

## Read-only

This skill **reports findings; it never edits, commits, or pushes code.** Running the app and driving a browser in runtime mode is evaluation, not a code change — it stays within read-only. The orchestrator (`validate`) or the developer (`pr-review` curation) acts on the findings.

## See also

- `frontend-ui-engineering` — the build standard you review against (don't restate it)
- `find-patterns` — map the component inventory before judging reuse/duplication
- `api-and-interface-design` — props/interface design for area (c)
- [`.claude/references/accessibility-checklist.md`](../../references/accessibility-checklist.md) — baseline WCAG 2.1 AA bar
- [`.claude/references/performance-checklist.md`](../../references/performance-checklist.md) — frontend performance checks
- `browser-testing-with-devtools` — drives the running app for runtime mode via the Chrome DevTools MCP (preferred); Playwright is used as a fallback when the Chrome MCP isn't configured
- `qa-review` — the testing half (test coverage / e2e evidence); design-review is the frontend/UX/a11y lens, not a test-coverage check
- `impeccable` — authors design direction and visual craft; design-review audits, it doesn't create

## Non-negotiables

Do not approve a frontend change with accessibility violations, duplicated/missed-reuse components, or broken cross-component state/data flow. Do not block on subjective polish — flag it advisory. Do not edit code. Use the fixed severity vocabulary. When runtime can't run, fall back to static and say so — never hard-fail.
