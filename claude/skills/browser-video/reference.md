# Browser Video Reference

Details for [SKILL.md](SKILL.md). Paths below are relative to the skill directory.

## CLI

```bash
node scripts/record.mjs <steps-file> [--out <dir>]
node scripts/record.mjs --check
sh scripts/preflight.sh
```

| Flag | Meaning |
|------|---------|
| `--out <dir>` | Output directory. Default: a new `browser-video-*` directory under the OS temp dir. |
| `--check` | Verify Playwright resolves from the current directory and Chromium launches. Used by `preflight.sh`. |

`--out` is refused if it is a symlink, not a directory, not owned by the current user, or writable by group or others. A missing directory is created with mode `0700`.

Run from the project that has Playwright: it is resolved from the current directory (`playwright`, `@playwright/test`, then `playwright-core`), not from the skill directory.

### Exit codes

| Command | Code | Meaning |
|---------|------|---------|
| `record.mjs` | 0 | MP4 written. The last stdout line is its path. |
| | 1 | Run failed: Playwright or Chromium missing, a step threw, or encoding failed. |
| | 2 | Usage error or invalid steps file. |
| `record.mjs --check` | 0 | Ready. |
| | 3 | Playwright not resolvable from the current directory. |
| | 4 | Chromium cannot launch. |
| `preflight.sh` | 0 | All dependencies present. |
| | 1 | Something is missing; each item is printed with its fix. |
| | 2 | Usage error. |

## Steps file

An ES module (`.mjs`) with a default export, or named exports, of one object:

| Field | Required | Rule |
|-------|----------|------|
| `name` | yes | Matches `^[A-Za-z0-9._-]+$`, no leading `.`. Output file is `<name>.mp4`. |
| `url` | yes | Absolute `http:`, `https:` or `file:` URL, opened first. A username or password in it is rejected (exit `2`). |
| `viewport` | no | `{ width, height }`, both positive even integers. Default `1440x900`. Also the video size. |
| `steps` | yes | Non-empty array. |

An invalid file exits 2 with `invalid steps file: <reason>`.

### Step fields

| Field | Required | Rule |
|-------|----------|------|
| `id` | yes | Matches `^[A-Za-z0-9._-]+$`, no leading `.`. Used in `timeline.json` and `failure-<id>.png`. |
| `act` | yes | `async (page, h) => {}`. `page` is a Playwright `Page`; `h` is the helper set below. |
| `caption` | no | Non-empty string, shown for the step. Two lines at most; longer text is clipped. |
| `hold` | no | Minimum step length in ms, a finite number `>= 0`. Default `1500`. The step lasts `max(hold, time act took)`. |

Per step: the caption is shown, `act` runs, the overlay and caption are re-applied (a navigation inside `act` replaces the document), the step waits out `hold`, then the caption and any card are cleared. A `500` ms hold is added after the last step.

## Helpers (`h`)

| Helper | Behaviour |
|--------|-----------|
| `h.expectVisible(locator, timeout = 5000)` | Wait until visible; throws a readable error otherwise. |
| `h.click(locator)` | Scroll into view, glide the pointer to the centre (250 to 900 ms by distance), then click. |
| `h.type(locator, text)` | Scroll into view, then type with a 60 ms delay per key. Does not click first. |
| `h.scroll(pixels)` | Mouse-wheel scroll in 50 px steps, then a 150 ms settle. Negative scrolls up. |
| `h.highlight(locator, ms = 1200)` | Draw a ring around the element for `ms`, then remove it. |
| `h.card({ title, body? })` | Full-screen title card. `title` is a required non-empty string; `body` is optional text under it, kept to a few lines. Stays until the end of the current step, then is cleared automatically. |

Helpers throw on a missing or hidden element. The pointer, ring, caption and card live in a closed shadow root, so Playwright locators never match their text.

The caption sits at the bottom centre. Keep the subject of a captioned step above the bottom 120 px.

## Outputs

Written to the output directory:

| File | When | Content |
|------|------|---------|
| `<name>.mp4` | success | H.264, yuv420p, 30 fps, no audio, `+faststart`. |
| `timeline.json` | success | Step offsets, below. |
| `<random id>.webm` | failure only | Raw recording; its path is printed as `webm kept: <path>`. |
| `failure-<id>.png` | a step failed | Screenshot at the failure. |

Failed runs leave the `.webm` and PNG behind; both can show logged-in content. Delete them.

```json
{
  "steps": [
    { "id": "open", "start": 0.62, "end": 2.14 },
    { "id": "save", "start": 2.14, "end": 3.9, "caption": "Save changes" }
  ]
}
```

`start` and `end` are seconds from the start of the video. `caption` is present only when the step has one. The video can run up to about 0.1 s ahead of these numbers, so sample frames at `start + 0.3` to `0.7` of `end - start`.

The encode appends cloned final frames and cuts at the measured run length, because Playwright can drop a static tail from the webm.

## Extract a frame

```bash
sh ${CLAUDE_SKILL_DIR}/scripts/frame.sh <file>.mp4 <seconds> <out>.png
```

Pick `<seconds>` from `timeline.json`, mid-step. Open the PNG to look at it. `frame.sh` accepts only an existing `.mp4`, a non-negative decimal number of seconds and a `.png` output that is not a symlink (exit `2` otherwise), then runs `ffmpeg -nostdin -hide_banner -loglevel error -y -ss <seconds> -f mp4 -i <mp4> -frames:v 1 <png>`. It overwrites the PNG, and exits `1` when ffmpeg fails or `<seconds>` is past the end of the video.

## Example

```js
// steps.mjs
export default {
  name: 'profile-flow',
  url: 'https://example.com/profile',
  viewport: { width: 1280, height: 720 },
  steps: [
    {
      id: 'open',
      hold: 1500,
      act: (page, h) => h.expectVisible(page.getByRole('heading', { name: 'Profile' })),
    },
    {
      id: 'fill',
      caption: 'Enter a name',
      act: async (page, h) => {
        await h.highlight(page.getByLabel('Name'), 600);
        await h.click(page.getByLabel('Name'));
        await h.type(page.getByLabel('Name'), 'Ada Lovelace');
      },
    },
    {
      id: 'section',
      act: (page, h) => h.card({ title: 'Saving' }),
      hold: 1800,
    },
    {
      id: 'save',
      caption: 'Save changes',
      act: async (page, h) => {
        await h.click(page.getByRole('button', { name: 'Save' }));
        await h.expectVisible(page.getByText('Saved'));
      },
    },
  ],
};
```

Run it from the project:

```bash
node ${CLAUDE_SKILL_DIR}/scripts/record.mjs steps.mjs
```
