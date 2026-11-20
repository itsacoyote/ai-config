#!/usr/bin/env bash
# record-smoke.sh — real-run suite for browser-video/scripts/record.mjs
#
# Drives the real recorder against a local fixture page: Playwright, Chromium and
# ffmpeg must work. BROWSER_VIDEO_PROJECT names a directory whose node_modules has
# playwright and an installed Chromium; the suite prints SKIP and exits 0 without it.
#
# Usage:  BROWSER_VIDEO_PROJECT=<dir> bash claude/skills/browser-video/scripts/tests/record-smoke.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.
#
# Linux (Playwright image; its tag must match the Playwright version installed below), from the repo root:
#   docker run --rm -it --ipc=host -v "$PWD":/repo:ro mcr.microsoft.com/playwright:v1.65.1-noble bash
# then inside the container (the image has no ffmpeg; node_modules stays container-local):
#   mkdir /scratch && cd /scratch && npm init -y && npm i playwright@1.65.1
#   apt-get update && apt-get install -y ffmpeg
#   sh /repo/claude/skills/browser-video/scripts/preflight.sh
#   bash /repo/claude/skills/browser-video/scripts/tests/preflight-test.sh
#   BROWSER_VIDEO_PROJECT=/scratch bash /repo/claude/skills/browser-video/scripts/tests/record-smoke.sh
# Missing Chromium system libraries (preflight reports --with-deps, --check exits 4) reproduce in a plain
#   docker run --rm -it -v "$PWD":/repo:ro node:22-bookworm-slim bash
# after npm i playwright and npx playwright install chromium (no --with-deps).

set -u
exec </dev/null

if [ -z "${BROWSER_VIDEO_PROJECT:-}" ]; then
  echo "SKIP: BROWSER_VIDEO_PROJECT is not set (a directory with playwright and Chromium installed)"
  exit 0
fi

pass=0
fail=0
ok()      { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok()  { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

# check <name> <command...> — passes when the command exits 0.
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else not_ok "$name"; fi
}

HERE="$(cd "$(dirname "$0")" && pwd -P)"
RECORD="$HERE/../record.mjs"
FIX="$HERE/fixtures"
PROJECT="$(cd "$BROWSER_VIDEO_PROJECT" && pwd -P)"

TMPBASE="${TMPDIR:-/tmp}"; TMPBASE="${TMPBASE%/}"
TMP=$(mktemp -d "$TMPBASE/browser-video-test.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "mktemp produced no directory" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# A directory with no node_modules anywhere above it.
BARE="$TMP/bare"; mkdir -p "$BARE"
unset NODE_PATH

OUT=''; ERR=''; STATUS=0
# run_in <cwd> [record.mjs args...] — stdout in OUT, stderr in ERR, exit status in STATUS.
run_in() {
  local from="$1"; shift
  OUT="$(cd "$from" && node "$RECORD" "$@" 2>"$TMP/stderr")"
  STATUS=$?
  ERR="$(cat "$TMP/stderr")"
}

frame_at() { ffmpeg -nostdin -hide_banner -loglevel error -y -ss "$2" -i "$1" -frames:v 1 "$3"; }

probe() { ffprobe -v error -select_streams v:0 -show_entries "$2" -of default=noprint_wrappers=1:nokey=1 "$1"; }

# Seconds at <fraction> of step <id>'s span in <outdir>/timeline.json.
time_of() {
  node -e '
const { steps } = JSON.parse(require("fs").readFileSync(process.argv[1] + "/timeline.json", "utf8"));
const s = steps.find((x) => x.id === process.argv[2]);
process.stdout.write(s ? (s.start + (s.end - s.start) * Number(process.argv[3])).toFixed(3) : "-1");
' "$1" "$2" "$3"
}

# Value recorded by the overlay fixture's act functions, or <missing>.
obs() {
  node -e '
let lines = [];
try { lines = require("fs").readFileSync(process.argv[1], "utf8").trim().split("\n").map((l) => JSON.parse(l)); } catch {}
const hit = lines.filter((l) => l.key === process.argv[2]).pop();
process.stdout.write(hit === undefined ? "<missing>" : String(hit.value));
' "$OBS_FILE" "$1"
}

# Crops are w:h:x:y. stat_of prints "YMIN YMAX YAVG" of the filtered frame, or nothing when ffmpeg failed
# (output is captured before matching, so an empty value can never satisfy a comparison below).
stat_of() { # <filtergraph over [0:v] (and [1:v])> <png>...
  local graph="$1" text input args=()
  shift
  for input in "$@"; do args+=(-i "$input"); done
  text="$(ffmpeg -nostdin -hide_banner -loglevel error "${args[@]}" \
    -filter_complex "$graph,signalstats,metadata=print:file=-" -f null - 2>&1)"
  printf '%s\n' "$text" | awk -F= '
    /^lavfi.signalstats.YMIN=/ { lo = $2 }
    /^lavfi.signalstats.YMAX=/ { hi = $2 }
    /^lavfi.signalstats.YAVG=/ { avg = $2 }
    END { if (lo != "" && hi != "" && avg != "") print lo, hi, avg }'
}
# Mean absolute luma difference of the same crop in two frames: ~0 for identical content.
diff_avg() { # <png a> <png b> <crop>
  local s
  s="$(stat_of "[0:v]crop=$3[a];[1:v]crop=$3[b];[a][b]blend=all_mode=difference" "$1" "$2")"
  [ -n "$s" ] && printf '%s\n' "$s" | awk '{ print $3 }'
}
luma_range() { # <png> <crop>
  local s
  s="$(stat_of "[0:v]crop=$2" "$1")"
  [ -n "$s" ] && printf '%s\n' "$s" | awk '{ print $2 - $1 }'
}
# An empty number never passes either comparison.
gt() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
lt() { [ -n "$1" ] && awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }

check_eq() { # <name> <obs key> <expected>
  local got
  got="$(obs "$2")"
  if [ "$got" = "$3" ]; then ok "$1"; else not_ok "$1 (got: $got)"; fi
}
check_diff() { # <name> <png a> <png b> <crop> <lt|gt> <bound>
  local v
  v="$(diff_avg "$2" "$3" "$4")"
  if "$5" "$v" "$6"; then ok "$1 (diff $v)"; else not_ok "$1 (diff $v)"; fi
}
check_range() { # <name> <png> <crop> <lt|gt> <bound>
  local v
  v="$(luma_range "$2" "$3")"
  if "$4" "$v" "$5"; then ok "$1 (range $v)"; else not_ok "$1 (range $v)"; fi
}

# ---- happy path -------------------------------------------------------------
section "fixture flow"
OUTDIR="$TMP/out/nested"
run_in "$PROJECT" "$FIX/steps.mjs" --out "$OUTDIR"
MP4="$OUTDIR/fixture-flow.mp4"
LAST="$(printf '%s\n' "$OUT" | tail -n 1)"

if [ "$STATUS" -eq 0 ]; then ok "fixture run exits 0"; else not_ok "fixture run exits 0 (got $STATUS: $ERR)"; fi

SPEC="$(probe "$MP4" stream=codec_name,pix_fmt,width,height 2>&1 | tr '\n' ' ')"
if [ "$SPEC" = "h264 1440 900 yuv420p " ]; then
  ok "records the fixture flow to an h264 yuv420p mp4 at 1440x900"
else
  not_ok "records the fixture flow to an h264 yuv420p mp4 at 1440x900 (got: $SPEC)"
fi

DUR="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MP4" 2>&1)"
# Expected 800 + 900 ms from the fixture steps, written as a literal.
if awk -v d="$DUR" 'BEGIN { exit !(d >= 1.7) }'; then
  ok "mp4 duration is at least the sum of step holds"
else
  not_ok "mp4 duration is at least the sum of step holds (got $DUR)"
fi

if [ "$LAST" = "$MP4" ] && [ "${LAST#/}" != "$LAST" ]; then
  ok "last stdout line is the absolute mp4 path"
else
  not_ok "last stdout line is the absolute mp4 path (got: $LAST)"
fi

if [ -s "$OUTDIR/timeline.json" ] && [ -s "$MP4" ] && [ -z "$(ls "$OUTDIR" | grep '\.webm$')" ]; then
  ok "--out creates the directory and writes the mp4 and timeline.json there"
else
  not_ok "--out creates the directory and writes the mp4 and timeline.json there ($(ls "$OUTDIR" 2>&1 | tr '\n' ' '))"
fi

TL="$(node -e '
const { steps } = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const dur = Number(process.argv[2]);
const ids = steps.map((s) => s.id).join(",");
let good = ids === "open,go" && steps.every((s) => s.start >= 0 && s.end > s.start);
for (let i = 1; i < steps.length; i++) good = good && steps[i].start >= steps[i - 1].end;
good = good && steps[steps.length - 1].end <= dur;
process.stdout.write(good ? "good" : "bad " + JSON.stringify(steps));
' "$OUTDIR/timeline.json" "$DUR")"
if [ "$TL" = "good" ]; then
  ok "timeline offsets are monotonic and the last end is no later than the video duration"
else
  not_ok "timeline offsets are monotonic and the last end is no later than the video duration ($TL)"
fi

# Pins the exact frame command that the skill docs tell users to run.
if frame_at "$MP4" 0.5 "$TMP/frame.png" && [ -s "$TMP/frame.png" ]; then
  ok "a frame can be extracted from the mp4"
else
  not_ok "a frame can be extracted from the mp4"
fi

section "custom viewport"
run_in "$PROJECT" "$FIX/steps-viewport.mjs" --out "$TMP/small"
SPEC="$(probe "$TMP/small/small.mp4" stream=width,height 2>&1 | tr '\n' ' ')"
if [ "$STATUS" -eq 0 ] && [ "$SPEC" = "800 450 " ]; then
  ok "honours a custom even viewport from the steps file"
else
  not_ok "honours a custom even viewport from the steps file (status $STATUS, got: $SPEC)"
fi

# ---- failing step -----------------------------------------------------------
section "failing step"
run_in "$PROJECT" "$FIX/steps-missing.mjs" --out "$TMP/failed"
if [ "$STATUS" -eq 1 ] && [ -s "$TMP/failed/failure-no-such-element.png" ]; then
  ok "fails with exit 1 and writes failure-<id>.png when expectVisible misses"
else
  not_ok "fails with exit 1 and writes failure-<id>.png when expectVisible misses (status $STATUS: $ERR)"
fi

LAST="$(printf '%s\n' "$OUT" | tail -n 1)"
case "$LAST" in *.mp4) ends_mp4=1 ;; *) ends_mp4=0 ;; esac
if [ "$ends_mp4" -eq 0 ] && [ -z "$(ls "$TMP/failed" | grep '\.mp4$')" ] && [ -n "$(ls "$TMP/failed" | grep '\.webm$')" ]; then
  ok "on a failing step stdout does not end with an .mp4 path and no mp4 is written"
else
  not_ok "on a failing step stdout does not end with an .mp4 path and no mp4 is written"
fi

# ---- overlay: pointer, captions, cards, paced helpers -----------------------
section "overlay flow"
OV="$TMP/overlay"
OBS_FILE="$TMP/obs.jsonl"
rm -f "$OBS_FILE"
BV_OBS="$OBS_FILE" run_in "$PROJECT" "$FIX/steps-overlay.mjs" --out "$OV"
if [ "$STATUS" -eq 0 ]; then ok "overlay fixture run exits 0"; else not_ok "overlay fixture run exits 0 (got $STATUS: $ERR)"; fi

check_eq "click through the overlay changes the page (button label updates)" label "Saved"
check_eq "type enters the full text into the input" typed "Ada Lovelace"
# Playwright text locators must not see the closed shadow root, or a caption that repeats page text breaks strict locators.
check_eq "a caption whose text equals the button label does not change what getByText resolves to (count stays 1)" captionCount 1
check_eq "card text is invisible to page locators" cardTextCount 0
check_eq "page state set before a card survives it (input value still present after the card step)" valueAfterCard "Ada Lovelace"
check_eq "scroll moves the page" scrolled true

# Thresholds, each set from a measured run with a wide margin. Mean luma difference is 0..255, range is YMAX-YMIN.
SAME_MAX=2         # identical content measured 0 to 0.4 (static h264 noise), so about 5x margin
CAPTION_MIN=20     # caption bar over the page measured 33.6 to 60.6, so at least 1.6x margin
POINTER_MIN=8      # pointer arrow in the small crop measured 29.4, so about 3.7x margin
CARD_MIN=30        # opaque dark card over a white page measured 168 to 175, so about 5x margin
TEXT_RANGE_MIN=100 # white text on dark, or black on white, measured 211 to 219, so about 2x margin
FLAT_RANGE_MAX=12  # a flat card region measured 0, so margin for encode noise

# Crops are w:h:x:y in the 1440x900 fixture viewport. Each one depends on a fixture or overlay value:
#   CAPTION_CROP   caption bar: centred (x 720), 40px above the bottom edge, about 70px tall, over #save (left 600, top 800)
#   POINTER_CROP   the pointer tip rests on the centre of #inert (page.html: left 900, top 200, 240x100)
#   AWAY_CROP      blank page between #name (top 400) and #save (top 800), clear of caption and pointer
#   CARD_CROP      middle of the viewport, where the card centres its title
#   TITLE_CROP     the one-line title of the title-only card (centred at y 450)
#   BODY_CROP      the one-line body of the title-and-body card: title (83 px) + gap (32) + body (48) centred at y 450 puts the body at y 483-531
#   BELOW_BODY_CROP blank card area under the body
#   H1_CROP        the page heading, top left; the pointer start (48, 48) sits inside it in page frames
INERT_CX=$((900 + 240 / 2)); INERT_CY=$((200 + 100 / 2))
CAPTION_CROP="400:100:520:780"
POINTER_CROP="36:40:$((INERT_CX - 4)):$((INERT_CY - 4))"
AWAY_CROP="300:100:500:500"
CARD_CROP="400:200:520:350"
TITLE_CROP="400:90:520:405"
H1_CROP="600:100:40:40"
BODY_CROP="400:40:520:490"
BELOW_BODY_CROP="400:40:520:600"

# idle and aim show identical page content, so a diff between them can only come from the caption or the pointer.
OVMP4="$OV/overlay-flow.mp4"
FR="$TMP/frames"; mkdir -p "$FR"
frame_at "$OVMP4" "$(time_of "$OV" idle 0.3)" "$FR/idle-early.png"
frame_at "$OVMP4" "$(time_of "$OV" idle 0.7)" "$FR/idle-late.png"
frame_at "$OVMP4" "$(time_of "$OV" aim 0.5)" "$FR/aim.png"
frame_at "$OVMP4" "$(time_of "$OV" type 0.5)" "$FR/type.png"
frame_at "$OVMP4" "$(time_of "$OV" card 0.5)" "$FR/card.png"
frame_at "$OVMP4" "$(time_of "$OV" card-body 0.5)" "$FR/card-body.png"
frame_at "$OVMP4" "$(time_of "$OV" save 0.5)" "$FR/save.png"
frame_at "$OVMP4" "$(time_of "$OV" reattach 0.5)" "$FR/reattached.png"
# The video leads timeline.json by up to about 0.1 s on Linux, so sample mid-step: a point within 0.1 s of a step edge shows the neighbouring step.
frame_at "$OVMP4" "$(time_of "$OV" settle 0.5)" "$FR/settled.png"
frame_at "$OVMP4" "$(time_of "$OV" finish 0.5)" "$FR/finish.png"
# 1.2 of the 1.2 s hold is 0.24 s past the step end, inside the 0.5 s trailing hold.
frame_at "$OVMP4" "$(time_of "$OV" finish 1.2)" "$FR/final.png"

# Positive control: two uncaptioned frames of one step. Without it, a noisy encode could make the compares below pass alone.
check_diff "control: caption region of two frames of one uncaptioned step is the same" \
  "$FR/idle-early.png" "$FR/idle-late.png" "$CAPTION_CROP" lt "$SAME_MAX"
# Without the overlay's repainting pixel, Chromium sent no frames for the static opening step on Linux (about 1 run in 3),
# the video started late, and the card showed 1.8 s before its timeline offset. A quarter second early is clear of the 0.1 s normal lead.
frame_at "$OVMP4" "$(time_of "$OV" card -0.15)" "$FR/pre-card.png"
check_range "the page, not the card, is shown just before the card step (video offsets match timeline.json)" "$FR/pre-card.png" "$H1_CROP" gt "$TEXT_RANGE_MIN"
check_diff "caption-bar region of a captioned step differs from the same region of an uncaptioned step" \
  "$FR/idle-late.png" "$FR/aim.png" "$CAPTION_CROP" gt "$CAPTION_MIN"
check_diff "an uncaptioned step after a captioned one shows no caption" \
  "$FR/idle-late.png" "$FR/type.png" "$CAPTION_CROP" lt "$SAME_MAX"

# The last step has no successor to reset the caption, so only the end-of-step clear can remove it.
check_diff "control: the last step's caption is drawn during the step" \
  "$FR/settled.png" "$FR/finish.png" "$CAPTION_CROP" gt "$CAPTION_MIN"
check_diff "caption is cleared at the end of its step" \
  "$FR/settled.png" "$FR/final.png" "$CAPTION_CROP" lt "$SAME_MAX"

check_diff "the overlay is attached again after the page removes its host (the caption is drawn)" \
  "$FR/settled.png" "$FR/reattached.png" "$CAPTION_CROP" gt "$CAPTION_MIN"

check_diff "control: a region away from caption and pointer is the same in both frames" \
  "$FR/idle-late.png" "$FR/aim.png" "$AWAY_CROP" lt "$SAME_MAX"
check_diff "region around the pointer target differs from the same region in a frame with the pointer elsewhere" \
  "$FR/idle-late.png" "$FR/aim.png" "$POINTER_CROP" gt "$POINTER_MIN"
check_diff "centre region of the card frame differs from the page frame" \
  "$FR/idle-late.png" "$FR/card.png" "$CARD_CROP" gt "$CARD_MIN"

check_range "card title region is not a single flat colour (text is drawn)" "$FR/card.png" "$TITLE_CROP" gt "$TEXT_RANGE_MIN"
check_range "card body text is drawn (body region is not flat)" "$FR/card-body.png" "$BODY_CROP" gt "$TEXT_RANGE_MIN"
check_range "control: the card region under the body is flat" "$FR/card-body.png" "$BELOW_BODY_CROP" lt "$FLAT_RANGE_MAX"
check_range "control: the page heading region has visible text on a page frame" "$FR/idle-late.png" "$H1_CROP" gt "$TEXT_RANGE_MIN"
check_range "card hides the page for its step (heading region is flat)" "$FR/card.png" "$H1_CROP" lt "$FLAT_RANGE_MAX"
check_range "card hides the page for its step only: the next step shows the real page" "$FR/save.png" "$H1_CROP" gt "$TEXT_RANGE_MIN"

run_in "$PROJECT" "$FIX/steps-highlight-missing.mjs" --out "$TMP/hl-failed"
if [ "$STATUS" -eq 1 ] && [ -s "$TMP/hl-failed/failure-no-highlight-target.png" ]; then
  ok "fails with exit 1 and writes failure-<id>.png when highlight targets a missing element"
else
  not_ok "fails with exit 1 and writes failure-<id>.png when highlight targets a missing element (status $STATUS: $ERR)"
fi

# ---- screencast frames on a static page ---------------------------------------
section "static page screencast"
# Chromium sends a screencast frame only when the page repaints. Measured over 1.5 s on the fixture page:
# 31 frames with the overlay's repainting pixel, 1 without. The webm starts at its first frame, so a quiet
# opening step is cut from the video when no frames flow.
MIN_STATIC_FRAMES=10
FRAMES="$(cd "$PROJECT" && node "$HERE/screencast-frames.mjs" "$FIX/page.html" 2>/dev/null)"
if [ -n "$FRAMES" ] && [ "$FRAMES" -ge "$MIN_STATIC_FRAMES" ] 2>/dev/null; then
  ok "a static page with the overlay keeps emitting screencast frames ($FRAMES)"
else
  not_ok "a static page with the overlay keeps emitting screencast frames (got: ${FRAMES:-nothing}, need $MIN_STATIC_FRAMES)"
fi

# ---- invalid steps files ----------------------------------------------------
# Run from BARE, where Playwright cannot resolve: exit 2 (not 1) proves the
# validation ran before any attempt to load Playwright or launch a browser.
section "steps validation"
expect_usage_error() {
  local name="$1" fixture="$2"
  run_in "$BARE" "$FIX/$fixture"
  if [ "$STATUS" -eq 2 ]; then ok "$name (exit 2)"; else not_ok "$name (exit 2, got $STATUS: $ERR)"; fi
}
expect_usage_error "rejects a steps file with an empty steps array" invalid-empty.mjs
expect_usage_error "rejects a step whose act is not a function" invalid-bad-act.mjs
expect_usage_error "rejects a negative hold" invalid-neg-hold.mjs
expect_usage_error "rejects a relative url" invalid-rel-url.mjs
expect_usage_error "rejects a name with a path separator" invalid-bad-name.mjs
expect_usage_error "rejects an odd viewport width" invalid-odd-viewport.mjs
expect_usage_error "rejects a step id with a path separator" invalid-bad-step-id.mjs
expect_usage_error "rejects a caption that is not a string" invalid-bad-caption.mjs

# ---- --out and error-output safety -------------------------------------------
section "out dir and redaction"
mkdir -p "$TMP/real-out"
ln -s "$TMP/real-out" "$TMP/link-out"
run_in "$PROJECT" "$FIX/steps.mjs" --out "$TMP/link-out"
if [ "$STATUS" -eq 2 ] && [ -z "$(ls "$TMP/real-out")" ]; then
  ok "refuses an --out path that is a symlink (exit 2)"
else
  not_ok "refuses an --out path that is a symlink (exit 2, got $STATUS: $ERR)"
fi

run_in "$PROJECT" "$FIX/steps.mjs" --out "$TMP/new-out"
MODE="$(node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$TMP/new-out")"
if [ "$STATUS" -eq 0 ] && [ "$MODE" = "700" ]; then
  ok "creates a new --out directory with mode 700"
else
  not_ok "creates a new --out directory with mode 700 (status $STATUS, mode $MODE)"
fi

run_in "$PROJECT" "$FIX/steps-nav-fail.mjs" --out "$TMP/nav-out"
# Exit 1 plus a non-empty error is the positive control: the run really failed in navigation.
if [ "$STATUS" -eq 1 ] && [ -n "$ERR" ] && ! printf '%s\n%s' "$OUT" "$ERR" | grep -qE 'secret|token=abc'; then
  ok "a failed navigation does not print url credentials or query string"
else
  not_ok "a failed navigation does not print url credentials or query string (status $STATUS: $ERR)"
fi

# ---- environment problems ---------------------------------------------------
section "missing playwright / chromium"
run_in "$BARE" "$FIX/steps.mjs" --out "$TMP/bare-out"
if [ "$STATUS" -ne 0 ] && printf '%s' "$ERR" | grep -q 'preflight.sh'; then
  ok "a run from a directory without playwright exits non-zero and points to preflight.sh"
else
  not_ok "a run from a directory without playwright exits non-zero and points to preflight.sh (status $STATUS: $ERR)"
fi

run_in "$PROJECT" --check
if [ "$STATUS" -eq 0 ]; then ok "--check exits 0 in a project with playwright and chromium"; else not_ok "--check exits 0 in a project with playwright and chromium (got $STATUS: $OUT $ERR)"; fi

run_in "$BARE" --check
if [ "$STATUS" -eq 3 ] && [ "$OUT" = "missing: playwright" ]; then
  ok "--check exits 3 and prints 'missing: playwright' in a directory without playwright"
else
  not_ok "--check exits 3 and prints 'missing: playwright' in a directory without playwright (status $STATUS: $OUT)"
fi

mkdir -p "$TMP/no-browsers"
OUT="$(cd "$PROJECT" && PLAYWRIGHT_BROWSERS_PATH="$TMP/no-browsers" node "$RECORD" --check 2>/dev/null)"
STATUS=$?
if [ "$STATUS" -eq 4 ] && [ "$OUT" = "missing: chromium" ]; then
  ok "--check exits 4 and prints 'missing: chromium' when the browser cannot launch"
else
  not_ok "--check exits 4 and prints 'missing: chromium' when the browser cannot launch (status $STATUS: $OUT)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
