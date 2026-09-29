# QA Pass

Verify the PR's claim, not just the diff. Confirm the feature actually works as described —
not that it typechecks or passed CI. A feature can pass CI and still be wired to nothing,
return the wrong shape, or be unreachable; this pass catches that.

## Read CI status from the context file

Read the `## CI checks` section of `pr-context.md` for the suites' result. Don't re-run the
unit/integration/e2e suites — they already ran in CI. Spend this pass on what CI can't tell
you: whether the feature is reachable and does what the description claims.

## Verify the claim

Start from each claim in the context file's `Description` section. Confirm: the path is wired
end to end, the feature is reachable, inputs and outputs match what's promised, and the
obvious edge cases hold.

## Two paths, depending on what the harness can do

**Can run commands** (shell, dev server, browser driver available): exercise the real
behavior — hit the endpoint, drive the UI, run the CLI, walk the actual flow — and report what
you observed: the command run and its actual output, or the UI steps and what rendered.

**Cannot run commands** (read-only session): trace the code path statically instead — follow
the wiring from entry point to output and confirm it's consistent with the claim. Then hand the
developer a copy-pasteable verification package:

- **UI feature** — the exact route/URL, any login or seed data needed, numbered steps to reach
  and exercise the feature, and what correct behavior looks like at each step.
- **API/CLI/backend feature** — a `curl`/httpie command or CLI invocation, any setup (auth
  token, seed data), and the expected output.

The developer runs it and reports back — their observation is the actual verification, not
yours.

## Never launder a trace into "works"

"Traced and looks correct" and "exercised and observed working" are different results and must
be reported differently. If you could not run it yourself, report **not exercised** — never
upgrade a trace to a pass. Report one of: **works** (observed working, by you or the
developer) / **broken** (observed failure) / **not exercised** (traced only, verification
package handed off).

## Finding format

For each gap or issue found while verifying:

- **Severity** — CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Where** — file:line
- **What** — the gap (unreachable path, wrong output shape, claim not met)
- **Why** — what breaks for the user, or what the claim promised but didn't deliver
- **Suggested comment text** — text ready to post as a review comment
