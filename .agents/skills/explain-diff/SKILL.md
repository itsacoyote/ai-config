---
name: explain-diff
description: Use when the user wants a rich HTML explainer or walkthrough of a code change — a diff, commit range, branch, or PR — rather than a quick chat-level summary.
metadata:
  category: git-maintenance
---
<!-- cSpell:words Kleppmann -->

# Explain Diff

Produce a rich, self-contained HTML explainer of a code change — the kind someone reads to
*understand* a change, not a quick summary. Write it with the clarity and flow of Martin
Kleppmann: engaging, classic style, with smooth transitions between sections.

## When NOT to use

- The user just wants a quick "what changed here?" — answer in chat; don't build a page.
- The change is trivial (a rename, a version bump, a one-line fix) — the scaffold is overkill.
- The user wants the change *critiqued* for correctness/security/tests — use `senior-review`,
  `security-scan`, or the PR-review skills. This skill **explains**, it doesn't judge.

## Step 1 — Resolve the change and gather context

Resolve `scripts/explain-diff.sh` relative to this skill directory and run its absolute path first. It stamps today's date, builds the dated output path, and dumps the diff plus orientation (status / commits / changed files, or the PR description) in one call:

```bash
sh <skill-dir>/scripts/explain-diff.sh prepare [target] [--slug <short-name>]
```

Pass the `target` for what you're explaining — ask if it's ambiguous:

- **Working tree** — omit the target (uses `git diff` / `--staged`).
- **A pull request** — the PR number (uses `gh pr diff` / `gh pr view`, unless the project documents another GitHub tool).
- **A commit range / single commit** — `a..b` / `a...b` (uses `git diff <range>`).
- **A branch or ref** — the ref name. The script assumes the default branch as the base and says
  so — confirm that's the branch's actual base; that's a judgment call the script can't make.

Then read **broadly around** the change so the Background is accurate — don't explain only the
touched lines. Use [`analyze-code`](../analyze-code/SKILL.md) to understand an unfamiliar module
and [`find-patterns`](../find-patterns/SKILL.md) for the conventions it follows.

## Sections

One long scrollable page with a table of contents at the top — **no tabs** for the top-level
structure. In order:

- **Background** — the existing system this change touches. The reader's level is unknown, so
  give a *deep background for beginners* (clearly marked skippable for those already familiar),
  then a *narrow background* directly relevant to the change.
- **Intuition** — the core idea of the change. Essence over detail. Use concrete examples with
  toy data, and lean on figures and diagrams.
- **Code** — a high-level walkthrough of the actual changes, grouped and ordered so they build
  understandably (not file-by-file if that obscures the story).
- **Quiz** — five interactive multiple-choice questions, medium difficulty: hard enough that you
  must understand the change to answer, but not gotchas. On click, tell the reader whether they
  were right and give feedback.

## Output

Write a single self-contained HTML file — **inline** CSS and JS, no external CDNs, fonts, or
network requests. That keeps it working offline and ensures nothing about the diff leaves the
machine.

- **Location & name:** use the dated `/tmp` path from `prepare` (e.g.
  `/tmp/2026-01-12-explanation-<slug>.html`). The date prefix keeps the files time-sorted and out
  of version control.
- **Validate before finishing (required):** run the check and fix anything it reports as `FAIL`:

  ```bash
  sh <skill-dir>/scripts/explain-diff.sh check <file>
  ```

  It confirms the file is self-contained (no external loads — the offline/security guarantee),
  that code blocks won't collapse newlines, and that the filename is date-prefixed.
- **Then:** print the path and open it — `open <path>` on macOS (`xdg-open` on Linux).
- **Responsive:** basic mobile styling so it's readable on a phone. A dark-mode variant via
  `@media (prefers-color-scheme: dark)` is a nice touch.

## Readability

Make the page easy to scan and hard to lose your place in:

- Lead with the point, then support it.
- Short paragraphs; break big ideas into bullet lists or numbered steps.
- Strong, frequent headings so the structure is visible; generous spacing; readable line length
  (~60–70 characters).
- Optional visual anchors (an icon or emoji on major section headings) help the eye track
  sections — use them sparingly, not on every item.
- Use **callouts** for key concepts, definitions, and important edge cases.

## Diagrams

- Pick a **small number of diagram families** and reuse them across the explanation. Useful kinds:
  - A simplified mock of the app UI, to explain UI changes.
  - A system / data-flow diagram between components — **include example data** flowing through it.
- **No ASCII diagrams** — build diagrams as simple HTML/CSS. Use HTML lists for lists of things.
- **Code blocks:** always use `<pre>` tags. If you use a styled `<div>` instead, its CSS **must**
  include `white-space: pre-wrap`, or the browser collapses every newline into a single line. The
  `check` step (see Output) verifies this before you finish.

## Sharing through a hosted artifact (opt-in only)

The local file above is always the default. Only upload it through a harness's hosted-artifact feature when the user explicitly asks to share it. Warn first that this sends the content off-machine and the provider may cache or index it even if later deleted. Keep confidential work code local.
