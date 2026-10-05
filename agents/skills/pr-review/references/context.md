# Context Pass

Orient before reviewing: establish what the PR intends, what area it touches, and what
discussion already happened — so the other passes work from a shared understanding instead
of re-deriving it. Read-only.

## Read the context file first

Pull from `pr-context.md` (the context file layout defined in ADR 0014) by section:

- `Description` — the PR's own stated intent (title + body)
- `Linked issues` — the problem the issue frames, if any
- `Changed files` / `Diff` — the touched area
- `Conversation comments` / `Reviews` / `Review comments` — what's already been discussed,
  fixed, or explicitly accepted

## Orient

1. **Intent** — what is this PR trying to do, grounded in the description and linked issue.
2. **Area touched** — the modules/files touched; survey them to understand what they do and
   how they fit the rest of the codebase.
3. **Conventions & patterns** — naming, structure, error handling, and testing conventions
   already in place in the touched area; note inconsistencies the change introduces or
   inherits.
4. **Already settled — do not re-raise** — from the conversation and review comments, list
   points already raised and resolved (fixed, or explicitly accepted), so later passes don't
   re-post them.
5. **Notes for the other passes** — risk areas, surprising coupling, and gaps between the
   stated intent and the actual diff.

Stay scoped to this PR — survey the touched area for context, don't audit the whole repo.

## Return

- Intent
- Area touched
- Conventions & patterns (plus inconsistencies)
- Already settled — do not re-raise (list)
- Notes for the other passes (risks, coupling, intent-vs-diff gaps)

## Finding format

This pass produces an orientation brief, not a findings list. Where something concrete is
worth flagging directly (an inconsistency worth a comment), use the shared format the other
passes use:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:line
- **What** — the issue
- **Why** — the impact
- **Suggested comment text** — text ready to post as a review comment
