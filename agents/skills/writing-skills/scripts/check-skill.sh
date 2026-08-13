#!/bin/sh
# check-skill.sh — lightweight validation for Agent Skills in this library.
#
# It validates the plain, single-line frontmatter style used by this repository. It is not a
# complete YAML parser; use skills-ref validate as well when that tool is already present.
#
# Usage: check-skill.sh <skill-dir|SKILL.md>
#        check-skill.sh --all

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
BUNDLED_SKILLS_ROOT="$(CDPATH= cd "$SCRIPT_DIR/../.." && pwd)"

resolve_md() {
  if [ -d "$1" ]; then
    echo "$1/SKILL.md"
  else
    echo "$1"
  fi
}

char_count() {
  printf '%s' "$1" | wc -m | tr -d ' '
}

check_one() {
  md="$1"
  dir="$(dirname "$md")"
  fail=0

  echo "▶ $md"

  if [ ! -f "$md" ]; then
    echo "  ✗ no SKILL.md at this path"
    return 1
  fi

  scan_dir="$(CDPATH= cd "$dir" 2>/dev/null && pwd -P)"
  if [ -z "$scan_dir" ]; then
    echo "  ✗ cannot resolve skill directory"
    return 1
  fi

  if [ "$(sed -n '1p' "$md")" != "---" ]; then
    echo "  ✗ frontmatter: file does not start with '---'"
    return 1
  fi

  fm_end="$(awk 'NR > 1 && /^---[[:space:]]*$/ { print NR; exit }' "$md")"
  if [ -z "$fm_end" ]; then
    echo "  ✗ frontmatter: no closing '---'"
    return 1
  fi

  fm="$(sed -n "2,$((fm_end - 1))p" "$md")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  compatibility="$(printf '%s\n' "$fm" | sed -n 's/^compatibility:[[:space:]]*//p' | head -1)"
  compatibility_present="$(printf '%s\n' "$fm" | grep -c '^compatibility:' || true)"

  if [ -n "$name" ]; then
    echo "  ✓ name: $name"
  else
    echo "  ✗ missing 'name:'"
    fail=1
  fi

  if [ -n "$desc" ]; then
    echo "  ✓ description present"
  else
    echo "  ✗ missing 'description:'"
    fail=1
  fi

  if [ -n "$name" ]; then
    name_chars="$(char_count "$name")"
    if [ "$name_chars" -gt 64 ]; then
      echo "  ✗ name is $name_chars characters; maximum is 64"
      fail=1
    fi

    printf '%s' "$name" | grep -qE '^[a-z0-9-]+$' || {
      echo "  ✗ name must contain only lowercase letters, numbers, and hyphens"
      fail=1
    }

    case "$name" in
      -*|*-)
        echo "  ✗ name must not start or end with a hyphen"
        fail=1
        ;;
    esac

    case "$name" in
      *--*)
        echo "  ✗ name must not contain consecutive hyphens"
        fail=1
        ;;
    esac

    dirname_name="$(basename "$dir")"
    if [ "$name" != "$dirname_name" ]; then
      echo "  ✗ name '$name' does not match directory '$dirname_name'"
      fail=1
    fi
  fi

  if [ -n "$desc" ]; then
    desc_chars="$(char_count "$desc")"
    if [ "$desc_chars" -gt 1024 ]; then
      echo "  ✗ description is $desc_chars characters; maximum is 1024"
      fail=1
    fi

    case "$desc" in
      "Use when"*) : ;;
      *)
        echo "  ✗ description must start with 'Use when'"
        fail=1
        ;;
    esac
  fi

  if [ "$compatibility_present" -gt 0 ] && [ -z "$compatibility" ]; then
    echo "  ✗ compatibility must not be empty when present"
    fail=1
  elif [ -n "$compatibility" ]; then
    compatibility_chars="$(char_count "$compatibility")"
    if [ "$compatibility_chars" -gt 500 ]; then
      echo "  ✗ compatibility is $compatibility_chars characters; maximum is 500"
      fail=1
    fi
  fi

  files_list="$(mktemp "${TMPDIR:-/tmp}/check-skill-files.XXXXXX")"
  links_list="$(mktemp "${TMPDIR:-/tmp}/check-skill-links.XXXXXX")"
  find "$scan_dir" -type f -name '*.md' -print >"$files_list"

  while IFS= read -r source_md; do
    grep -oE '\]\([^)]+\)' "$source_md" 2>/dev/null |
      sed 's/^](//; s/)$//' >"$links_list" || true

    while IFS= read -r link; do
      case "$link" in
        \<*\>) link="${link#<}"; link="${link%>}" ;;
      esac

      case "$link" in
        http://*|https://*|mailto:*|\#*) continue ;;
      esac

      target="${link%%#*}"
      [ -n "$target" ] || continue

      case "$target" in
        /*) path="$ROOT/${target#/}" ;;
        .agents/*|agents/*) path="$ROOT/$target" ;;
        *) path="$(dirname "$source_md")/$target" ;;
      esac

      if [ ! -e "$path" ]; then
        echo "  ✗ dead link in $source_md: $link"
        fail=1
      fi
    done <"$links_list"
  done <"$files_list"

  rm -f "$files_list" "$links_list"

  if [ "$fail" -eq 0 ]; then
    echo "  ✓ links resolve"
  fi

  words="$(sed -n "$((fm_end + 1)),\$p" "$md" | wc -w | tr -d ' ')"
  lines="$(sed -n "$((fm_end + 1)),\$p" "$md" | wc -l | tr -d ' ')"
  echo "  ℹ body $words words, $lines lines"

  return "$fail"
}

overall=0

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,9p' "$0"
  exit 0
fi

if [ "${1:-}" = "--all" ]; then
  if [ -d "$ROOT/agents/skills" ]; then
    skills_root="$ROOT/agents/skills"
  elif [ -d "$ROOT/.agents/skills" ]; then
    skills_root="$ROOT/.agents/skills"
  else
    skills_root="$BUNDLED_SKILLS_ROOT"
  fi

  checked=0
  for dir in "$skills_root"/*/; do
    [ -d "$dir" ] || continue
    checked=$((checked + 1))
    check_one "$dir/SKILL.md" || overall=1
    echo
  done

  if [ "$checked" -eq 0 ]; then
    echo "✗ no skills found under $skills_root"
    exit 1
  fi
elif [ -n "${1:-}" ]; then
  check_one "$(resolve_md "$1")" || overall=1
else
  echo "usage: check-skill.sh <skill-dir|SKILL.md> | --all" >&2
  exit 2
fi

if [ "$overall" -eq 0 ]; then
  echo "✓ all checks passed"
else
  echo "✗ one or more hard checks failed"
fi

exit "$overall"
