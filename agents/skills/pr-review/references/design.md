# Design Pass

Frontend-only pass: engage only when the diff touches component/markup/style files
(`.tsx/.jsx/.vue/.svelte`, CSS/SCSS/Tailwind, HTML/templates). If nothing matches, say "no
frontend changes — nothing to review" and stop; this is not a failure. Static review only —
don't run the app or drive a browser as part of this pass.

## Component reuse & duplication

Check the existing component inventory before judging the diff. Flag a new component that
duplicates or near-duplicates one that already exists, a reinvented pattern (modal, list,
form field, empty state) the codebase already has a component for, or copy-pasted
markup/logic that should be one shared component.

## Design-system correctness

Flag raw values (hex colors, arbitrary px) where a semantic token exists, spacing off the
project's scale, and the generic "AI aesthetic" (purple/indigo defaults, excess gradients,
`rounded-2xl` everywhere, oversized uniform padding) where it drifts from the project's actual
design system.

## Component architecture & interfaces

Composition over configuration (composable children, not a wall of boolean/variant props);
focused, single-responsibility components; minimal, well-typed props with no leaked
internals; data fetching separated from rendering.

## State & data flow

Right state location (local vs. lifted vs. context vs. URL vs. server vs. global);
prop-drilling deeper than ~3 levels that should be context or a restructure; server state kept
distinct from client state (no hand-rolled caching, no mirroring server data into client state).

## UX

Loading, empty, and error states all present (no blank screens); responsive behavior across
common breakpoints; focus moves sensibly on content change; no janky or surprising interaction.

## Accessibility

Review against the project's documented a11y standard if one exists; otherwise use baseline
WCAG 2.1 AA: keyboard navigation with visible focus, no keyboard traps, labeled inputs and
controls, sufficient contrast, color never the sole carrier of meaning.

## Severity gate

Block on: accessibility violations, missed component reuse/duplication, broken cross-component
state or data flow. Advisory only (LOW/INFO): subjective visual polish, spacing/typography taste.

## Finding format

Blockers first. For each:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:component:line
- **What** — the precise problem
- **Why** — the impact (broken state, inaccessible, duplicated effort)
- **Suggested comment text** — exactly what to change, ready to post as a review comment

If it holds up, say "design review approved" with one or two sentences on what was checked.
