# Commenting — Write the Non-Obvious, Nothing Else

How I want code comments written across all projects. The recurring failure is **over-commenting**: I add
prose that restates the code, narrates behavior, or repeats a rationale in several places. Reviewers treat that
as a defect. This rule is the corrective. (A project may layer its own stricter conventions on top — follow those
too; this is the personal baseline.)

## The one test

Before writing or keeping any comment, ask: **would a competent reader understand this code without it?**
If yes, delete it. The default is _no comment_ — a clear name or a small extracted function beats a sentence
describing what the code does.

## Comment the *why*, never the *what*

Names and control flow carry the _what_. Reserve comments for a _why_ the code genuinely can't carry: a
non-local constraint, a deliberate trade-off, a workaround and its reason, a security/timing invariant.

```ts
// BAD — restates the code / narrates the change / re-types the signature
// increment the retry count
retryCount++;

// GOOD — a decision the code can't express
// Cap backoff so a provider outage can't turn into a thundering herd.
const delayMs = Math.min(BASE_DELAY_MS * 2 ** retryCount, MAX_DELAY_MS);
```

## The keeper test (when a *why* is worth it)

Keep a comment when **omitting it would invite a plausible _wrong_ "fix."** These silent-breakage guards are
what earn a comment:

- An intentional oddity someone would "clean up" and break — e.g. a deliberate leading space in a string, a
  `// biome-ignore`, an ordering that looks arbitrary but isn't.
- A deliberate divergence from a sibling/expected pattern someone would "correct" back.

If you can't name the wrong fix it prevents, it's probably narration — cut it.

## One home per fact

A rationale lives in exactly one place. Do **not** repeat it.

- If a called function's JSDoc explains the why, the **call site keeps only what's local to it** and lets the
  name point to the helper. Don't restate the helper's reasoning at every call.
- Never duplicate the same explanatory line across multiple files. If a fact needs restating in five places, the
  comment is in the wrong place — extract the logic.

## Keep caller concerns at the call site

A pure or shared module's doc describes **its own contract** over its inputs. A constraint only the caller knows
(which value to pass and why) belongs where the call is made, not bolted onto the shared interface.

```ts
// BAD — leaks a caller's concern into a pure lib's interface (and duplicates the call-site note)
interface Step1State {
  /** Must be the address-gated flag from useWalletState, NOT useAccount's raw isConnected... */
  isConnected: boolean;
}

// GOOD — the pure interface is just types; the constraint lives at the call site that knows it
interface Step1State {
  isConnected: boolean;
}
// …at the call site:
// Pass useWalletState's address-gated isConnected, NOT useAccount's — the raw flag can be true
// while the address is transiently undefined, rendering the connected view with a blank address.
```

## No field-docs that restate names

An interface/param whose name already says it needs no doc line. `isLoading: boolean` does not need
`/** whether it is loading */`. Document a field only for a non-obvious unit, range, or constraint.

## Trim valid *whys* to their essence

Even a real why should be tight: a summary line plus telegraphic conditions, not a 4-line run-on. Prefer
one crisp clause over a paragraph re-explaining the flow.

## Cut narration, meta, and navigation filler

- **UX/behavior narration** — "…so the modal skips the manual Continue click." The code does that; don't say it.
- **Meta-commentary** — "the part worth pinning here is…", "note that…". Just state the fact.
- **Editor-provided navigation** — "Mirrors the block above", "see the function below". The editor shows structure.

## No speculative tails

Don't end a comment with "Revisit if…" / "TODO maybe…" hedges. If it's a real follow-up, file an issue and
move on. In teammate-facing text (comments, PR bodies), don't cite issue/ticket IDs colleagues can't resolve.

## Trivial/presentational code gets no narration

An emit-only button (`@click="$emit('click')"` + `defineEmits`) already reads as presentational — no paragraph
explaining that the parent owns the side effect.
