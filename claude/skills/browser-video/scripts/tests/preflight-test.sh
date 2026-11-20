#!/usr/bin/env bash
# preflight-test.sh — self-contained test suite for ../preflight.sh
#
# Every dependency preflight.sh looks at (node, ffmpeg, ffprobe, uname) is a stub on a
# PATH made only of symlinks, so "missing" means the file is absent from that directory
# rather than a flag the script could be tricked by. The node stub answers --version and
# `record.mjs --check` using the exit-code contract (0 ok, 3 playwright, 4 chromium).
#
# Usage:  bash claude/skills/browser-video/scripts/tests/preflight-test.sh
# Exits non-zero if any check fails.
#
# PREFLIGHT_UNDER_TEST points the suite at a mutated copy (mutation testing).
# SH_UNDER_TEST picks the shell that runs the script (default /bin/sh; try dash).

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PF=${PREFLIGHT_UNDER_TEST:-"$HERE/../preflight.sh"}
SH_BIN=${SH_UNDER_TEST:-/bin/sh}

pass=0
fail=0
ok() { printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
not_ok() { printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# check_equals <label> <expected> <actual>
check_equals() {
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1 (expected '$2', got '$3')"; fi
}

# check_contains <label> <needle> <captured-text>. Matching runs against text the caller
# already captured, never through a pipeline: under pipefail `cmd | grep -q` can report
# failure on a match (SIGPIPE) and an assertion inside a pipeline updates discarded counters.
check_contains() {
  if printf '%s\n' "$3" | grep -qF -- "$2"; then ok "$1"; else not_ok "$1 (missing '$2' in: $3)"; fi
}

check_not_contains() {
  if printf '%s\n' "$3" | grep -qF -- "$2"; then not_ok "$1 (unexpected '$2' in: $3)"; else ok "$1"; fi
}

section() { printf '\n%s\n' "$1"; }

# A run from a terminal must never block on a read.
exec </dev/null

TMP=$(mktemp -d "${TMPDIR:-/tmp}/preflight-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

LOG="$TMP/calls.log"
SED_REAL=$(command -v sed)

DEBIAN_RELEASE="$TMP/os-release-debian"
UBUNTU_LIKE_RELEASE="$TMP/os-release-ubuntu-like"
FEDORA_RELEASE="$TMP/os-release-fedora"
MISSING_RELEASE="$TMP/os-release-absent"
printf 'ID=debian\n' >"$DEBIAN_RELEASE"
printf 'ID=pop\nID_LIKE="ubuntu debian"\n' >"$UBUNTU_LIKE_RELEASE"
printf 'ID=fedora\nID_LIKE="rhel"\n' >"$FEDORA_RELEASE"

X264_LINE=' V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)'
X265_LINE=' V....D libx265              libx265 H.265 / HEVC (codec hevc)'
# The real-world trap: the rgb variant's description column also starts with "libx264 ".
X264RGB_LINE=' V....D libx264rgb           libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 RGB (codec h264rgb)'

# Writes the stubs. Behaviour is read from FAKE_* variables at run time, so one stub
# serves every case.
write_stub() { # write_stub <path> <body…>
  local path=$1
  shift
  printf '#!/bin/sh\n%s\n' "$*" >"$path"
  chmod +x "$path"
}

# make_bin <tool…> — builds a fresh PATH directory holding only the named stubs
# (plus the real sed, which preflight.sh uses only for -h). Echoes the directory.
make_bin() {
  local dir tool
  # mktemp, not a counter: callers run this in $(...), a subshell whose counter is discarded.
  dir=$(mktemp -d "$TMP/bin.XXXXXX")
  ln -s "$SED_REAL" "$dir/sed"
  for tool in "$@"; do
    case "$tool" in
      node)
        write_stub "$dir/node" 'echo "node $*" >>"$FAKE_LOG"
case "$1" in --version) echo "$FAKE_NODE_VERSION"; exit 0 ;; esac
case "$*" in
  *record.mjs*--check*)
    case "$FAKE_CHECK_EXIT" in
      3) echo "missing: playwright" ;;
      4) echo "missing: chromium" ;;
    esac
    exit "$FAKE_CHECK_EXIT" ;;
esac
exit 99'
        ;;
      ffmpeg)
        write_stub "$dir/ffmpeg" 'echo "ffmpeg $*" >>"$FAKE_LOG"
case "$*" in *-encoders*) printf "%s\n" "$FAKE_ENCODERS" ;; esac
exit 0'
        ;;
      ffprobe)
        write_stub "$dir/ffprobe" 'echo "ffprobe $*" >>"$FAKE_LOG"; exit 0'
        ;;
      uname)
        write_stub "$dir/uname" 'echo "$FAKE_UNAME"'
        ;;
    esac
  done
  printf '%s\n' "$dir"
}

reset_fixture() {
  FAKE_UNAME=Darwin
  FAKE_NODE_VERSION=v20.11.0
  FAKE_CHECK_EXIT=0
  FAKE_ENCODERS=$X264_LINE
  OS_RELEASE=$MISSING_RELEASE
  : >"$LOG"
}

# run_pf <bindir> [args…] — sets OUT (stdout+stderr) and RC. env -i keeps the caller's
# PATH and variables out of what the script can see.
run_pf() {
  local bin=$1
  shift
  OUT=$(env -i HOME="$HOME" PATH="$bin" FAKE_LOG="$LOG" FAKE_UNAME="$FAKE_UNAME" \
    FAKE_NODE_VERSION="$FAKE_NODE_VERSION" FAKE_CHECK_EXIT="$FAKE_CHECK_EXIT" \
    FAKE_ENCODERS="$FAKE_ENCODERS" BROWSER_VIDEO_OS_RELEASE="$OS_RELEASE" \
    "$SH_BIN" "$PF" "$@" 2>&1)
  RC=$?
}

ALL="node ffmpeg ffprobe uname"
CALLS=''
refresh_calls() { CALLS=$(cat "$LOG"); }

# ---------------------------------------------------------------- tests

section 'baseline'

# Positive control first: every later "fails with …" case is only meaningful if the
# same fixture, with nothing removed, exits 0. A script that always exits 1 would
# otherwise pass every failure assertion below.
reset_fixture
run_pf "$(make_bin $ALL)"
refresh_calls
check_equals 'passes when every dependency is present (positive control): exit 0' 0 "$RC"
check_not_contains 'positive control prints no missing item' 'missing:' "$OUT"
# Would fail to catch: a libx264 check that never asks ffmpeg anything.
check_contains 'positive control asked ffmpeg for its encoders' 'ffmpeg -hide_banner -encoders' "$CALLS"
# Would fail to catch: a --check call that is skipped or pointed at the wrong file.
check_contains 'positive control ran record.mjs --check from the script directory' 'record.mjs --check' "$CALLS"
check_contains 'positive control ran the check next to preflight.sh' "${PF%/*}/record.mjs" "$CALLS"

section 'ffmpeg'

for pair in 'macOS:Darwin:brew install ffmpeg:' \
            'debian:Linux:sudo apt install ffmpeg:debian'; do
  label=${pair%%:*}; rest=${pair#*:}
  uname_out=${rest%%:*}; rest=${rest#*:}
  fix=${rest%:*}; distro=${rest##*:}

  reset_fixture
  FAKE_UNAME=$uname_out
  [ "$distro" = debian ] && OS_RELEASE=$DEBIAN_RELEASE
  run_pf "$(make_bin node ffprobe uname)"
  check_equals "$label: missing ffmpeg exits 1" 1 "$RC"
  check_contains "$label: missing ffmpeg fails with $fix" "$fix" "$OUT"
  check_contains "$label: missing ffmpeg names ffmpeg" 'missing: ffmpeg' "$OUT"
  # Would fail to catch: libx264 reported when ffmpeg itself is absent (a duplicate item).
  check_not_contains "$label: missing ffmpeg does not also report libx264" 'libx264' "$OUT"

  reset_fixture
  FAKE_UNAME=$uname_out
  [ "$distro" = debian ] && OS_RELEASE=$DEBIAN_RELEASE
  run_pf "$(make_bin node ffmpeg uname)"
  check_equals "$label: missing ffprobe exits 1" 1 "$RC"
  check_contains "$label: missing ffprobe fails with $fix" "$fix" "$OUT"
  check_contains "$label: missing ffprobe names ffprobe" 'missing: ffprobe' "$OUT"
  # Would fail to catch: ffmpeg reported missing because ffprobe is.
  check_not_contains "$label: missing ffprobe does not report ffmpeg" 'missing: ffmpeg' "$OUT"

  reset_fixture
  FAKE_UNAME=$uname_out
  FAKE_ENCODERS=$X265_LINE
  [ "$distro" = debian ] && OS_RELEASE=$DEBIAN_RELEASE
  run_pf "$(make_bin $ALL)"
  check_equals "$label: ffmpeg without libx264 exits 1" 1 "$RC"
  check_contains "$label: ffmpeg without libx264 fails with $fix" "$fix" "$OUT"
  check_contains "$label: ffmpeg without libx264 names libx264" 'missing: libx264' "$OUT"
done

reset_fixture
FAKE_UNAME=Linux
OS_RELEASE=$FEDORA_RELEASE
FAKE_ENCODERS=$X265_LINE
run_pf "$(make_bin $ALL)"
check_equals 'non-debian linux: missing libx264 exits 1' 1 "$RC"
check_contains 'non-debian linux: missing libx264 names the piece' 'ffmpeg build' "$OUT"
check_contains 'non-debian linux: missing libx264 mentions libx264' 'libx264' "$OUT"
# Would fail to catch: a debian or macOS command printed for an unknown distro.
check_not_contains 'non-debian linux: no apt command' 'apt' "$OUT"
check_not_contains 'non-debian linux: no brew command' 'brew' "$OUT"

reset_fixture
FAKE_UNAME=Linux
OS_RELEASE=$UBUNTU_LIKE_RELEASE
run_pf "$(make_bin node ffprobe uname)"
# Would fail to catch: debian detection that only reads ID and ignores ID_LIKE.
check_contains 'linux with ID_LIKE containing ubuntu is treated as debian' 'sudo apt install ffmpeg' "$OUT"

reset_fixture
FAKE_UNAME=Linux
OS_RELEASE=$MISSING_RELEASE
run_pf "$(make_bin node ffprobe uname)"
check_equals 'linux without an os-release file still reports and exits 1' 1 "$RC"
check_not_contains 'linux without an os-release file gets no apt command' 'apt' "$OUT"

reset_fixture
FAKE_ENCODERS=$X264RGB_LINE
run_pf "$(make_bin $ALL)"
# Would fail to catch: a substring match for "libx264" that the rgb variant's own
# description column satisfies; it is a different encoder.
check_equals 'ffmpeg with only libx264rgb is not libx264: exit 1' 1 "$RC"
check_contains 'ffmpeg with only libx264rgb names libx264' 'missing: libx264' "$OUT"

section 'playwright and chromium'

reset_fixture
FAKE_CHECK_EXIT=3
run_pf "$(make_bin $ALL)"
check_equals 'check exit 3: exits 1' 1 "$RC"
check_contains 'check exit 3 fails with npm install playwright' 'npm install playwright' "$OUT"
check_contains 'check exit 3 names playwright' 'missing: playwright' "$OUT"
# Would fail to catch: exit codes 3 and 4 swapped.
check_not_contains 'check exit 3 does not print the chromium command' 'playwright install' "$OUT"

reset_fixture
FAKE_CHECK_EXIT=4
run_pf "$(make_bin $ALL)"
check_equals 'macOS: check exit 4 exits 1' 1 "$RC"
check_contains 'macOS: check exit 4 fails with npx playwright install chromium' 'npx playwright install chromium' "$OUT"
check_not_contains 'macOS: check exit 4 has no --with-deps' '--with-deps' "$OUT"
check_not_contains 'macOS: check exit 4 does not print the playwright command' 'npm install playwright' "$OUT"

reset_fixture
FAKE_CHECK_EXIT=4
FAKE_UNAME=Linux
OS_RELEASE=$DEBIAN_RELEASE
run_pf "$(make_bin $ALL)"
check_equals 'debian: check exit 4 exits 1' 1 "$RC"
check_contains 'debian: check exit 4 fails with npx playwright install --with-deps chromium' \
  'npx playwright install --with-deps chromium' "$OUT"
check_not_contains 'debian: check exit 4 has no unsupported-distro note' 'officially supports' "$OUT"

reset_fixture
FAKE_CHECK_EXIT=4
FAKE_UNAME=Linux
OS_RELEASE=$FEDORA_RELEASE
run_pf "$(make_bin $ALL)"
check_contains 'non-debian linux: check exit 4 still prints --with-deps chromium' \
  'npx playwright install --with-deps chromium' "$OUT"
check_contains 'non-debian linux: check exit 4 notes Debian and Ubuntu support' 'Debian' "$OUT"

reset_fixture
FAKE_CHECK_EXIT=7
run_pf "$(make_bin $ALL)"
# Would fail to catch: an unrecognised --check exit code treated as success.
check_equals 'unexpected check exit code exits 1' 1 "$RC"
check_contains 'unexpected check exit code is reported' 'exited with 7' "$OUT"

section 'node'

reset_fixture
FAKE_NODE_VERSION=v16.20.2
FAKE_CHECK_EXIT=3
run_pf "$(make_bin $ALL)"
refresh_calls
check_equals 'node older than 18 exits 1' 1 "$RC"
check_contains 'node older than 18 says to install Node 18 or later' 'Node 18 or later' "$OUT"
check_contains 'node older than 18 reports the found version' '16.20.2' "$OUT"
check_contains 'node older than 18 says the playwright check was skipped' 'skipped' "$OUT"
# Would fail to catch: record.mjs --check still run on a node too old to run it.
check_not_contains 'node older than 18 skips record.mjs --check' 'record.mjs' "$CALLS"
check_not_contains 'node older than 18 prints no playwright fix' 'npm install playwright' "$OUT"

reset_fixture
run_pf "$(make_bin ffmpeg ffprobe uname)"
check_equals 'missing node exits 1' 1 "$RC"
check_contains 'missing node says to install Node 18 or later' 'Node 18 or later' "$OUT"
# Would fail to catch: a missing node reported as an old one (found unknown) because the presence check was dropped.
check_not_contains 'missing node is not reported as an old version' 'found' "$OUT"
check_contains 'missing node says the playwright check was skipped' 'skipped' "$OUT"
check_not_contains 'missing node prints no playwright fix' 'npm install playwright' "$OUT"

# Would fail to catch: an off-by-one such as -gt 18, which rejects the minimum version.
reset_fixture
FAKE_NODE_VERSION=v18.0.0
run_pf "$(make_bin $ALL)"
check_equals 'node 18.0.0 is accepted' 0 "$RC"

# Would fail to catch: a string comparison, where "9" sorts after "18".
reset_fixture
FAKE_NODE_VERSION=v9.11.2
run_pf "$(make_bin $ALL)"
check_equals 'node 9 is rejected (numeric, not lexical, comparison)' 1 "$RC"

reset_fixture
FAKE_NODE_VERSION=garbage
run_pf "$(make_bin $ALL)"
# Would fail to catch: a non-numeric version crashing the comparison and passing.
check_equals 'unparseable node version is treated as too old' 1 "$RC"
check_contains 'unparseable node version still says to install Node 18 or later' 'Node 18 or later' "$OUT"
# Would fail to catch: dropping the numeric guard, which still fails but leaks the shell's
# own "integer expression expected" / "Illegal number" error into the report.
check_not_contains 'unparseable node version prints no shell test error (bash)' 'expected' "$OUT"
check_not_contains 'unparseable node version prints no shell test error (dash)' 'llegal' "$OUT"

section 'aggregate'

reset_fixture
FAKE_CHECK_EXIT=3
run_pf "$(make_bin node uname)"
check_equals 'everything missing exits 1' 1 "$RC"
# Would fail to catch: a script that stops at the first missing item.
check_contains 'reports ffmpeg' 'missing: ffmpeg' "$OUT"
check_contains 'reports ffprobe' 'missing: ffprobe' "$OUT"
check_contains 'reports playwright in the same run' 'missing: playwright' "$OUT"
check_contains 'prints the macOS ffmpeg fix' 'brew install ffmpeg' "$OUT"
check_contains 'prints the playwright fix' 'npm install playwright' "$OUT"

reset_fixture
FAKE_UNAME=Linux
OS_RELEASE=$DEBIAN_RELEASE
FAKE_NODE_VERSION=v14.0.0
FAKE_ENCODERS=$X265_LINE
run_pf "$(make_bin node ffmpeg uname)"
check_contains 'node, ffprobe and libx264 are all reported together: node' 'missing: node' "$OUT"
check_contains 'node, ffprobe and libx264 are all reported together: ffprobe' 'missing: ffprobe' "$OUT"
check_contains 'node, ffprobe and libx264 are all reported together: libx264' 'missing: libx264' "$OUT"

section 'usage'

reset_fixture
run_pf "$(make_bin $ALL)" -h
refresh_calls
check_equals '-h exits 0' 0 "$RC"
check_contains '-h prints the usage header' 'Usage:' "$OUT"
check_contains '-h documents the exit codes' 'Exit:' "$OUT"
# Would fail to catch: help text that also runs the checks, or leaks the script body.
check_equals '-h runs no checks' '' "$CALLS"
check_not_contains '-h prints only the header' 'set -u' "$OUT"

reset_fixture
run_pf "$(make_bin $ALL)" --bogus
refresh_calls
check_equals 'an unknown flag exits 2' 2 "$RC"
check_contains 'an unknown flag is named on stderr as an error' 'error: unknown argument: --bogus' "$OUT"
check_equals 'an unknown flag runs no checks' '' "$CALLS"

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
