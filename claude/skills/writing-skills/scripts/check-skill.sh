#!/bin/sh
# check-skill.sh — mechanical lint for a SKILL.md against the repo's invariants.
#
# Encodes the deterministic, checkable rules from the writing-skills skill and
# CLAUDE.md so they aren't eyeballed each time. It does NOT judge quality —
# whether the description is trigger-led, whether keywords are right, whether the
# body earns its length: that stays with the author (this is GREEN-phase plumbing).
#
# Checks (✗ = hard fail, ⚠ = warning, ℹ = info):
#   ✗ frontmatter present and closed (--- … ---)
#   ✗ has both `name:` and `description:`
#   ✗ name matches ^[a-z0-9-]+$
#   ✗ name not a built-in command (code-review, security-review, review, verify, init, run)
#   ✗ frontmatter block ≤ 1024 chars
#   ✗ no dead links — every relative markdown link target resolves on disk
#   ⚠ description starts with "Use when" (strong convention, not universal)
#   ℹ body word count
#
# Usage:  check-skill.sh <skill-dir|SKILL.md>     check one
#         check-skill.sh --all                     check every .claude/skills/*/SKILL.md
# Exit:   0 all checked skills pass; 1 a hard check failed; 2 usage.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
COLLISIONS="code-review security-review review verify init run"

resolve_md() {  # accept a dir or a file, echo the SKILL.md path
  if [ -d "$1" ]; then echo "$1/SKILL.md"
  else echo "$1"; fi
}

check_one() {  # $1 = SKILL.md path; echoes results; returns 1 on hard fail
  md="$1"; dir="$(dirname "$md")"; fail=0
  echo "▶ $md"
  if [ ! -f "$md" ]; then echo "  ✗ no SKILL.md at this path"; return 1; fi

  # Frontmatter must open on line 1 and close on a later '---'.
  if [ "$(sed -n '1p' "$md")" != "---" ]; then
    echo "  ✗ frontmatter: file does not start with '---'"; return 1
  fi
  fm_end="$(awk 'NR>1 && /^---[[:space:]]*$/ { print NR; exit }' "$md")"
  if [ -z "$fm_end" ]; then echo "  ✗ frontmatter: no closing '---'"; return 1; fi
  fm="$(sed -n "2,$((fm_end-1))p" "$md")"

  # name + description present
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  [ -n "$name" ] && echo "  ✓ name: $name" || { echo "  ✗ missing 'name:'"; fail=1; }
  [ -n "$desc" ] && echo "  ✓ description present" || { echo "  ✗ missing 'description:'"; fail=1; }

  # name shape + collisions
  if [ -n "$name" ]; then
    printf '%s' "$name" | grep -qE '^[a-z0-9-]+$' || { echo "  ✗ name '$name' must match ^[a-z0-9-]+\$"; fail=1; }
    for c in $COLLISIONS; do
      [ "$name" = "$c" ] && { echo "  ✗ name '$name' collides with a built-in command"; fail=1; }
    done
  fi

  # description convention (warn only — sync/standup/etc. legitimately differ)
  if [ -n "$desc" ]; then
    case "$desc" in
      "Use when"*) : ;;
      *) echo "  ⚠ description does not start with \"Use when\" (triggers-led convention)" ;;
    esac
  fi

  # frontmatter byte budget
  fm_bytes="$(printf '%s\n' "$fm" | wc -c | tr -d ' ')"
  if [ "$fm_bytes" -le 1024 ]; then echo "  ✓ frontmatter ${fm_bytes}B (≤1024)"; else echo "  ✗ frontmatter ${fm_bytes}B exceeds 1024"; fail=1; fi

  # dead links: every relative markdown link target must exist on disk
  links="$(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed 's/^](//; s/)$//')"
  for l in $links; do
    case "$l" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target="${l%%#*}"                       # strip #anchor
    [ -n "$target" ] || continue
    case "$target" in
      /*)        path="$ROOT/${target#/}" ;;   # repo-absolute
      .claude/*) path="$ROOT/$target" ;;       # repo-root-relative
      *)         path="$dir/$target" ;;        # relative to this skill
    esac
    [ -e "$path" ] || { echo "  ✗ dead link: $l"; fail=1; }
  done
  [ "$fail" = 0 ] && echo "  ✓ links resolve"

  # body word count (informational — budget depends on skill type, a judgment)
  words="$(sed -n "$((fm_end+1)),\$p" "$md" | wc -w | tr -d ' ')"
  echo "  ℹ body ${words} words"

  return "$fail"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
overall=0
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then sed -n '2,24p' "$0"; exit 0; fi
if [ "${1:-}" = "--all" ]; then
  for d in "$ROOT"/.claude/skills/*/; do
    check_one "$d/SKILL.md" || overall=1
    echo
  done
elif [ -n "${1:-}" ]; then
  check_one "$(resolve_md "$1")" || overall=1
else
  echo "usage: check-skill.sh <skill-dir|SKILL.md> | --all" >&2; exit 2
fi

[ "$overall" = 0 ] && echo "✓ all checks passed" || echo "✗ one or more hard checks failed"
exit "$overall"
