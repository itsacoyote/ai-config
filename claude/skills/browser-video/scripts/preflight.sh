#!/bin/sh
# preflight.sh — check everything a browser-video recording needs, before recording.
#
# Reports every missing item (not just the first) with the exact fix command for
# this OS.
#
# Checks: node 18 or later, ffmpeg, ffprobe, the libx264 encoder, then
#   node record.mjs --check for Playwright (resolved from the current directory)
#   and a launchable Chromium. Run it from the project that has Playwright.
#
# Usage:
#   sh preflight.sh        run all checks
#   sh preflight.sh -h     print this help
#
# Exit: 0 ok; 1 a dependency is missing; 2 usage error.

set -u

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR=.
case "$0" in */*) SCRIPT_DIR=${0%/*} ;; esac

os=other
case "$(uname -s 2>/dev/null)" in
  Darwin) os=macos ;;
  Linux)
    os=linux
    release=${BROWSER_VIDEO_OS_RELEASE:-/etc/os-release}
    if [ -r "$release" ]; then
      distro=$(ID=; ID_LIKE=; . "$release" >/dev/null 2>&1; echo "$ID $ID_LIKE")
      case " $distro " in *debian*|*ubuntu*) os=debian ;; esac
    fi
    ;;
esac

missing=0

report() {
  printf 'missing: %s\n  fix: %s\n' "$1" "$2"
  missing=$((missing + 1))
}

ffmpeg_fix() {
  case "$os" in
    macos) echo 'brew install ffmpeg' ;;
    debian) echo 'sudo apt install ffmpeg' ;;
    *) echo 'install an ffmpeg build with libx264 (it provides ffmpeg and ffprobe) using your package manager' ;;
  esac
}

node_ok=0
if command -v node >/dev/null 2>&1; then
  version=$(node --version 2>/dev/null)
  version=${version#v}
  major=${version%%.*}
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  if [ "$major" -ge 18 ]; then
    node_ok=1
  else
    report "node 18 or later (found ${version:-unknown})" 'install Node 18 or later'
  fi
else
  report node 'install Node 18 or later'
fi

if command -v ffmpeg >/dev/null 2>&1; then
  encoders=$(ffmpeg -hide_banner -encoders 2>&1)
  # Anchored to the name column: libx264rgb's description also starts with "libx264 ".
  case "$encoders" in
    *' V'?????' libx264 '*) ;;
    *) report libx264 "$(ffmpeg_fix)" ;;
  esac
else
  report ffmpeg "$(ffmpeg_fix)"
fi

command -v ffprobe >/dev/null 2>&1 || report ffprobe "$(ffmpeg_fix)"

if [ "$node_ok" = 1 ]; then
  node "$SCRIPT_DIR/record.mjs" --check >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) ;;
    3) report playwright 'npm install playwright   (run in the project)' ;;
    4)
      fix='npx playwright install --with-deps chromium'
      [ "$os" = macos ] && fix='npx playwright install chromium'
      report chromium "$fix"
      if [ "$os" = linux ]; then
        echo '  note: Playwright officially supports Debian and Ubuntu only; other distributions may need extra system libraries.'
      fi
      ;;
    *)
      echo "error: record.mjs --check exited with $rc" >&2
      missing=$((missing + 1))
      ;;
  esac
else
  echo 'skipped: playwright and chromium checks need a working node'
fi

if [ "$missing" -gt 0 ]; then
  exit 1
fi
echo 'ok: all browser-video dependencies are present'
