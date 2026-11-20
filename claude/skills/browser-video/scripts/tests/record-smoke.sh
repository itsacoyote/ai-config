#!/usr/bin/env bash
# record-smoke.sh — real-run suite for browser-video/scripts/record.mjs
#
# Drives the real recorder against a local fixture page: Playwright, Chromium and
# ffmpeg must work. BROWSER_VIDEO_PROJECT names a directory whose node_modules has
# playwright and an installed Chromium; the suite prints SKIP and exits 0 without it.
#
# Usage:  BROWSER_VIDEO_PROJECT=<dir> bash claude/skills/browser-video/scripts/tests/record-smoke.sh
# Exits non-zero on any failure. No CI, no runner — run it by hand.

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
