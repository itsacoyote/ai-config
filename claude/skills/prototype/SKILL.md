---
name: prototype
description: Use when a design question is cheaper to answer with throwaway code than with discussion — "does this state model / logic feel right?" or "what should this UI look like?" — before committing the decision into a plan or implementation.
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

In the feature workflow this is an optional side-step, not a step: reach for it during Define or Research when a spec conversation stalls on "how should it behave/look", or before Plan when a design decision is too abstract to settle on paper. The prototype's *answer* feeds the spec or plan; the prototype itself gets deleted.

## When NOT to use

- The question can be settled by reading code or docs — use `analyze-code` or `web-search`; a prototype is for questions only *interacting* with the idea can answer.
- The decision is already made and you're building the real thing — use `incremental-implementation` (and `frontend-ui-engineering` for UI). A "prototype" you intend to keep isn't a prototype; build it properly.
- The work is trivial — just do it.

## Pick a branch

Identify which question is being answered — from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build a tiny interactive terminal app that pushes the state machine through cases that are hard to reason about on paper.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious — but name it so a casual reader can see it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure.
2. **One command to run.** Whatever the project's existing task runner supports — `pnpm <name>`, `python <path>`, `bun <path>`, etc. The user must be able to start it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is _checking_, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype _runnable_, no abstractions. The point is to learn something fast and then delete it.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Delete or absorb when done.** When the prototype has answered its question, either delete it or fold the validated decision into the real code — don't leave it rotting in the repo. Code promoted from a prototype was written under prototype constraints (no tests, minimal error handling); rewrite it properly when folding it in, per `frontend-ui-engineering` for UI or the project's normal standards for logic.

## When done

The _answer_ is the only thing worth keeping from a prototype. Capture it durably, along with the question it was answering:

- **If the prototype belongs to tracked work** (a feature epic, a task, a `wayfinder` ticket), record it as a comment on that beads issue: `bd comment <id> "Prototype answered: <question> → <answer>"`. If the answer settled an architecturally significant decision, capture an ADR per `documentation-and-adrs`.
- **Otherwise** (no issue exists yet), put it in the message of the commit that deletes or folds in the prototype, or a `NOTES.md` next to the prototype as a placeholder until the verdict is in. If the answer kicks off tracked work, carry it into the feature epic's spec when `define` creates it.

If the user is around, that capture is a quick conversation; if not, leave the placeholder so they (or you, on the next pass) can fill in the verdict before deleting the prototype.
