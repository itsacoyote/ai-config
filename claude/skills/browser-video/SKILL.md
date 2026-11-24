---
name: browser-video
description: Use when you need an MP4 recording of a scripted browser flow — a visible pointer, captions and title cards over a real page, driven by Playwright.
allowed-tools: Read Bash(sh ${CLAUDE_SKILL_DIR}/scripts/preflight.sh*) Bash(node ${CLAUDE_SKILL_DIR}/scripts/record.mjs*) Bash(sh ${CLAUDE_SKILL_DIR}/scripts/frame.sh*)
---

# Browser Video

Record a scripted browser flow to an H.264 MP4. You write a steps file; `record.mjs` runs it in headless Chromium, draws a pointer, captions and cards over the page, and encodes the video plus a `timeline.json`.

Steps-file API, CLI flags, outputs, and a full example: [reference.md](reference.md).

## When NOT to use

- Writing or debugging E2E tests: use [playwright-expert](../playwright-expert/SKILL.md).
- Inspecting a live page (DOM, console, network, performance): use [browser-testing-with-devtools](../browser-testing-with-devtools/SKILL.md).
- A single screenshot: use Playwright directly.

## Prerequisites

- macOS or Debian/Ubuntu.
- Node 18 or later.
- Playwright installed in the project you run from.
- ffmpeg and ffprobe with libx264.

## Workflow

1. From the project that has Playwright, run `sh ${CLAUDE_SKILL_DIR}/scripts/preflight.sh`. It lists every missing dependency with the fix command for this OS. Fix them, then re-run.
2. Write a steps file (`.mjs`) following [reference.md](reference.md). Keep it outside the skill directory.
3. Record: `node ${CLAUDE_SKILL_DIR}/scripts/record.mjs <steps-file> [--out <dir>]`. On success the last stdout line is the MP4 path. The default output is a new temp directory.
4. Check the result. Read `timeline.json`, extract a few frames at mid-step offsets with `sh ${CLAUDE_SKILL_DIR}/scripts/frame.sh <mp4> <seconds> <out>.png`, and look at them. Fix the steps file and re-record if a caption hides content or a step shows the wrong state.
5. Give the user the MP4 path.

## Exit codes

`0` MP4 written, `1` the run failed, `2` usage error or invalid steps file. `preflight.sh` and `frame.sh`: `0` ok, `1` something is missing or failed, `2` usage error.

## Rules

- **The video can show logged-in data.** Review it before sharing. Keep it out of the repo: use the default temp dir or a directory outside the project.
- **A failed run leaves files behind.** The `.webm` and `failure-<id>.png` stay in the output dir and can show logged-in content. Delete them when done.
- **Run only from a trusted checkout.** `preflight.sh` and `record.mjs` both run the Playwright found from the current directory, and `record.mjs` executes the steps file. Do not run it in an untrusted checkout, such as a worktree used to review someone else's pull request.
- **Never put credentials in `url`;** it is rejected. If a page needs a session, add cookies or headers in the first step's `act` (`page.context().addCookies`, `page.setExtraHTTPHeaders`) with values read from the environment, then `page.goto`. Keep any saved storageState or cookie file (live session tokens) out of the repo.
- **Typed text is visible in the video** unless the field is `type=password`.
- **Captions cover content.** The caption sits at the bottom centre. Keep the subject of a captioned step above the bottom 120 px; scroll first.
- **Sample mid-step.** The video can run up to about 0.1 s ahead of `timeline.json`. Extract frames at `start + 0.3` to `0.7` of a step's span, not near boundaries.
- **Cards.** `h.card({ title, body? })` covers the page until the step ends. Both fields are plain text.
- **Step `id` and top-level `name` must match `^[A-Za-z0-9._-]+$`** and must not start with `.`.
