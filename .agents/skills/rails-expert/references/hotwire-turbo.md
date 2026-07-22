# Hotwire & Turbo

Durable judgment for choosing the right Hotwire tool. Confirm current tag/helper names and the Stimulus API in the official Hotwire docs via `web-search`.

## The decision: Drive vs Frame vs Stream vs Stimulus

Reach for the *least* powerful tool that does the job — it's simpler and degrades best.

| Tool | What it updates | Reach for it when |
|------|-----------------|-------------------|
| **Turbo Drive** | Whole page, via AJAX nav (default, free) | Normal links/forms — you usually do nothing |
| **Turbo Frame** | One bounded region, driven by *this user's* navigation | A part of the page (inline edit, modal, lazy section) should reload independently |
| **Turbo Stream** | One or many regions, with explicit append/replace/remove ops | A *single* action must change *multiple* places, or a *server-side event* must push to clients |
| **Stimulus** | No server round-trip; client-side DOM only | Pure interaction — toggles, dropdowns, debouncing, client validation |

Mental model: a **Frame** is "this box re-renders itself on navigation." A **Stream** is "the server says: do these mutations to these targets." If the change is one contiguous region tied to a click, use a Frame. If it's several targets at once, or originates from another user / a background job, use a Stream.

## Turbo Frames

A frame scopes navigation: links and forms inside it replace only the matching frame. The matching frame in the *response* must share the same ID — a frequent bug is an edit view whose frame ID doesn't match the show view, so nothing updates (or the whole page swaps).

- Lazy-load expensive/off-screen content with a `src` + lazy loading so it fetches only when needed.
- Use `dom_id(record)` for stable, collision-free frame IDs.
- Keep nesting shallow — deep frame trees are hard to reason about and to target.

## Turbo Streams

Two distinct triggers, same mechanism:

1. **Response to a request** — the controller responds with a `.turbo_stream` template listing the ops (append the new comment, reset the form). This is for the acting user only.
2. **Broadcast** — a model commit broadcasts a stream to everyone subscribed via `turbo_stream_from`. This is how real-time multi-user updates work, over Action Cable.

Broadcast from `after_*_commit`, never `after_save` — the record must be committed before subscribers (or a job) try to render it. Broadcasting is a side effect, so the "callbacks for business logic" caution applies: for anything beyond trivial fan-out, broadcast from a service or job rather than burying it in the model.

The core stream actions are append / prepend / replace / update / remove / before / after. Choosing between **replace** (swap the whole element including its frame/ID wrapper) and **update** (swap only the *contents*) is the common point of confusion — pick based on whether the wrapper itself should change.

## Stimulus

For behavior with no server involvement. Keep controllers small and reusable, named by behavior (`dropdown`, not `home-page`). Debounce high-frequency actions (search, autocomplete) so you don't flood the server. If a controller starts fetching and re-rendering server HTML, that's a signal it should be a Turbo Frame instead.

## Progressive enhancement

Build the plain HTML form/link that works without JavaScript first, then layer Frames/Streams on top. Hotwire is designed so the enhanced version is the same markup plus a wrapper — if the feature only works with JS, you've usually skipped a step.

## Performance

- Lazy-load off-screen frames.
- Debounce Stimulus actions tied to typing.
- Cache stream/frame partials where the content is stable.
- Prefer morphing for minimal DOM churn; minimize frame-nesting depth.
