#!/bin/sh
# frame.sh — extract one frame from a recording as a PNG, to check a step by eye.
#
# Arguments are validated so the skill can pre-approve this script instead of ffmpeg:
# the input must be an existing .mp4 file, seconds a non-negative decimal number,
# and the output path must end in .png and not be a symlink. The output file is overwritten.
#
# Usage:
#   sh frame.sh <file>.mp4 <seconds> <out>.png
#   sh frame.sh -h     print this help
#
# Exit: 0 PNG written; 1 ffmpeg is missing or failed; 2 usage error.

set -u

usage_error() {
  echo "error: $1" >&2
  echo "usage: sh frame.sh <file>.mp4 <seconds> <out>.png" >&2
  exit 2
}

case "${1:-}" in -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;; esac

[ $# -eq 3 ] || usage_error "expected 3 arguments, got $#"
input=$1
seconds=$2
output=$3

case "$input" in *.mp4) ;; *) usage_error "input must end in .mp4: $input" ;; esac
[ -f "$input" ] || usage_error "input is not an existing file: $input"
case "$seconds" in
  ''|*[!0-9.]*|.*|*.|*.*.*) usage_error "seconds must be a non-negative decimal number: $seconds" ;;
esac
case "$output" in *.png) ;; *) usage_error "output must end in .png: $output" ;; esac
[ ! -L "$output" ] || usage_error "output must not be a symlink: $output"

# A leading ./ keeps a path that starts with "-" from being read as an ffmpeg option.
case "$input" in /*) ;; *) input=./$input ;; esac
case "$output" in /*) ;; *) output=./$output ;; esac

command -v ffmpeg >/dev/null 2>&1 || { echo "error: ffmpeg not found; run preflight.sh" >&2; exit 1; }
# ffmpeg exits 0 and writes nothing for a time past the end, so a stale PNG must not pass the check below.
rm -f "$output"
ffmpeg -nostdin -hide_banner -loglevel error -y -ss "$seconds" -f mp4 -i "$input" -frames:v 1 "$output" || exit 1
[ -s "$output" ] || { echo "error: no frame at $seconds s (past the end of the video?)" >&2; exit 1; }
