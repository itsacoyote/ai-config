#!/bin/bash

set -u

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
VALIDATOR="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)/check-skill.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/check-skill-test.XXXXXX")"
PASS=0
FAIL=0

trap 'rm -rf "$TEST_ROOT"' EXIT

record_pass() {
  PASS=$((PASS + 1))
  printf '✓ %s\n' "$1"
}

record_fail() {
  FAIL=$((FAIL + 1))
  printf '✗ %s\n' "$1"
}

expect_success() {
  label="$1"
  shift

  if "$@" >"$TEST_ROOT/output" 2>&1; then
    record_pass "$label"
  else
    record_fail "$label"
    sed 's/^/    /' "$TEST_ROOT/output"
  fi
}

expect_failure() {
  label="$1"
  shift

  if "$@" >"$TEST_ROOT/output" 2>&1; then
    record_fail "$label"
    sed 's/^/    /' "$TEST_ROOT/output"
  else
    record_pass "$label"
  fi
}

expect_failure_matching() {
  label="$1"
  expected="$2"
  shift 2

  if "$@" >"$TEST_ROOT/output" 2>&1; then
    record_fail "$label"
    sed 's/^/    /' "$TEST_ROOT/output"
  elif grep -Fq "$expected" "$TEST_ROOT/output"; then
    record_pass "$label"
  else
    record_fail "$label"
    printf '    expected diagnostic: %s\n' "$expected"
    sed 's/^/    /' "$TEST_ROOT/output"
  fi
}

run_from() {
  working_dir="$1"
  shift

  (
    cd "$working_dir" || exit 1
    "$@"
  )
}

write_skill() {
  dir="$1"
  name="$2"
  description="$3"
  extra="${4:-}"

  mkdir -p "$dir"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$description"
    [ -n "$extra" ] && printf '%s\n' "$extra"
    printf '%s\n\n# Fixture\n' '---'
  } >"$dir/SKILL.md"
}

VALID="$TEST_ROOT/valid"
write_skill "$VALID" "valid" "Use when testing a valid fixture."
expect_success "accepts a valid skill" "$VALIDATOR" "$VALID"
expect_success "accepts a direct SKILL.md path" "$VALIDATOR" "$VALID/SKILL.md"

VALID_LINK="$TEST_ROOT/valid-link"
write_skill "$VALID_LINK" "valid-link" "Use when testing valid links."
mkdir -p "$VALID_LINK/references"
printf '%s\n' '# Valid' >"$VALID_LINK/references/valid.md"
printf '%s\n' '[Relative](references/valid.md)' '[External](https://example.com/a)' '[Anchor](#fixture)' >>"$VALID_LINK/SKILL.md"
expect_success "accepts relative, external, and anchor links" "$VALIDATOR" "$VALID_LINK"

SPACED_LINK="$TEST_ROOT/spaced-link"
write_skill "$SPACED_LINK" "spaced-link" "Use when testing a spaced link."
mkdir -p "$SPACED_LINK/references"
printf '%s\n' '# Valid' >"$SPACED_LINK/references/valid file.md"
printf '%s\n' '[Spaced](<references/valid file.md>)' >>"$SPACED_LINK/SKILL.md"
expect_success "accepts an angle-bracketed link containing spaces" "$VALIDATOR" "$SPACED_LINK"

MISMATCH="$TEST_ROOT/mismatch"
write_skill "$MISMATCH" "different-name" "Use when testing directory agreement."
expect_failure_matching "rejects directory/name mismatch" "does not match directory" "$VALIDATOR" "$MISMATCH"

BAD_CHAR="$TEST_ROOT/bad_name"
write_skill "$BAD_CHAR" "bad_name" "Use when testing invalid characters."
expect_failure_matching "rejects invalid name characters" "lowercase letters, numbers, and hyphens" "$VALIDATOR" "$BAD_CHAR"

BAD_TRIGGER="$TEST_ROOT/bad-trigger"
write_skill "$BAD_TRIGGER" "bad-trigger" "Tests a description without the required trigger prefix."
expect_failure_matching "rejects a non-trigger-led description" "must start with 'Use when'" "$VALIDATOR" "$BAD_TRIGGER"

CONSECUTIVE="$TEST_ROOT/bad--name"
write_skill "$CONSECUTIVE" "bad--name" "Use when testing consecutive hyphens."
expect_failure "rejects consecutive hyphens" "$VALIDATOR" "$CONSECUTIVE"

LEADING="$TEST_ROOT/-leading"
write_skill "$LEADING" "-leading" "Use when testing a leading hyphen."
expect_failure "rejects a leading hyphen" "$VALIDATOR" "$LEADING"

TRAILING="$TEST_ROOT/trailing-"
write_skill "$TRAILING" "trailing-" "Use when testing a trailing hyphen."
expect_failure "rejects a trailing hyphen" "$VALIDATOR" "$TRAILING"

LONG_NAME="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklm"
LONG_NAME_DIR="$TEST_ROOT/$LONG_NAME"
write_skill "$LONG_NAME_DIR" "$LONG_NAME" "Use when testing long names."
expect_failure "rejects names over 64 characters" "$VALIDATOR" "$LONG_NAME_DIR"

NAME_64="abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl"
NAME_64_DIR="$TEST_ROOT/$NAME_64"
write_skill "$NAME_64_DIR" "$NAME_64" "Use when testing the exact name boundary."
expect_success "accepts a 64-character name" "$VALIDATOR" "$NAME_64_DIR"

LONG_DESCRIPTION="$(awk 'BEGIN { for (i = 0; i < 1025; i++) printf "x" }')"
LONG_DESC_DIR="$TEST_ROOT/long-description"
write_skill "$LONG_DESC_DIR" "long-description" "$LONG_DESCRIPTION"
expect_failure "rejects descriptions over 1024 characters" "$VALIDATOR" "$LONG_DESC_DIR"

DESCRIPTION_PREFIX="Use when "
DESCRIPTION_PADDING="$(awk 'BEGIN { for (i = 0; i < 1015; i++) printf "x" }')"
DESCRIPTION_1024_DIR="$TEST_ROOT/description-1024"
write_skill "$DESCRIPTION_1024_DIR" "description-1024" "$DESCRIPTION_PREFIX$DESCRIPTION_PADDING"
expect_success "accepts a 1024-character description" "$VALIDATOR" "$DESCRIPTION_1024_DIR"

LONG_COMPATIBILITY="$(awk 'BEGIN { for (i = 0; i < 501; i++) printf "x" }')"
LONG_COMPAT_DIR="$TEST_ROOT/long-compatibility"
write_skill "$LONG_COMPAT_DIR" "long-compatibility" "Use when testing compatibility length." "compatibility: $LONG_COMPATIBILITY"
expect_failure "rejects compatibility over 500 characters" "$VALIDATOR" "$LONG_COMPAT_DIR"

COMPATIBILITY_500="$(awk 'BEGIN { for (i = 0; i < 500; i++) printf "x" }')"
COMPAT_500_DIR="$TEST_ROOT/compatibility-500"
write_skill "$COMPAT_500_DIR" "compatibility-500" "Use when testing the compatibility boundary." "compatibility: $COMPATIBILITY_500"
expect_success "accepts 500-character compatibility" "$VALIDATOR" "$COMPAT_500_DIR"

EMPTY_COMPAT_DIR="$TEST_ROOT/empty-compatibility"
write_skill "$EMPTY_COMPAT_DIR" "empty-compatibility" "Use when testing empty compatibility." "compatibility:"
expect_failure "rejects empty compatibility" "$VALIDATOR" "$EMPTY_COMPAT_DIR"

DEAD_LINK="$TEST_ROOT/dead-link"
write_skill "$DEAD_LINK" "dead-link" "Use when testing relative links."
printf '%s\n' '[Missing](references/missing.md)' >>"$DEAD_LINK/SKILL.md"
expect_failure "rejects dead relative links" "$VALIDATOR" "$DEAD_LINK"

SPACED_DEAD_LINK="$TEST_ROOT/spaced-dead-link"
write_skill "$SPACED_DEAD_LINK" "spaced-dead-link" "Use when testing a missing spaced link."
printf '%s\n' '[Missing](<references/missing file.md>)' >>"$SPACED_DEAD_LINK/SKILL.md"
expect_failure_matching "rejects a missing link containing spaces" "references/missing file.md" "$VALIDATOR" "$SPACED_DEAD_LINK"

REFERENCE_DEAD_LINK="$TEST_ROOT/reference-dead-link"
write_skill "$REFERENCE_DEAD_LINK" "reference-dead-link" "Use when testing links in bundled references."
mkdir -p "$REFERENCE_DEAD_LINK/references"
printf '%s\n' '[Missing](missing.md)' >"$REFERENCE_DEAD_LINK/references/guide.md"
expect_failure_matching "rejects a dead link inside a bundled reference" "dead link in" "$VALIDATOR" "$REFERENCE_DEAD_LINK"

SYMLINK_SOURCE="$TEST_ROOT/symlink-source"
write_skill "$SYMLINK_SOURCE" "symlink-source" "Use when testing a symlinked skill install."
mkdir -p "$SYMLINK_SOURCE/references"
printf '%s\n' '[Missing](missing.md)' >"$SYMLINK_SOURCE/references/guide.md"
SYMLINK_INSTALL_ROOT="$TEST_ROOT/symlink-install"
mkdir -p "$SYMLINK_INSTALL_ROOT"
ln -s "$SYMLINK_SOURCE" "$SYMLINK_INSTALL_ROOT/symlink-source"
expect_failure_matching "rejects a dead bundled-reference link through a skill symlink" "dead link in" "$VALIDATOR" "$SYMLINK_INSTALL_ROOT/symlink-source"

NO_OPEN="$TEST_ROOT/no-open"
mkdir -p "$NO_OPEN"
printf '%s\n' 'name: no-open' 'description: Use when testing frontmatter.' >"$NO_OPEN/SKILL.md"
expect_failure_matching "rejects missing opening frontmatter" "does not start with '---'" "$VALIDATOR" "$NO_OPEN"

NO_CLOSE="$TEST_ROOT/no-close"
mkdir -p "$NO_CLOSE"
printf '%s\n' '---' 'name: no-close' 'description: Use when testing frontmatter.' >"$NO_CLOSE/SKILL.md"
expect_failure_matching "rejects missing closing frontmatter" "no closing '---'" "$VALIDATOR" "$NO_CLOSE"

NO_NAME="$TEST_ROOT/no-name"
mkdir -p "$NO_NAME"
printf '%s\n' '---' 'description: Use when testing required fields.' '---' >"$NO_NAME/SKILL.md"
expect_failure_matching "rejects a missing name" "missing 'name:'" "$VALIDATOR" "$NO_NAME"

NO_DESCRIPTION="$TEST_ROOT/no-description"
mkdir -p "$NO_DESCRIPTION"
printf '%s\n' '---' 'name: no-description' '---' >"$NO_DESCRIPTION/SKILL.md"
expect_failure_matching "rejects a missing description" "missing 'description:'" "$VALIDATOR" "$NO_DESCRIPTION"

ALL_REPO="$TEST_ROOT/all-repo"
mkdir -p "$ALL_REPO/agents/skills"
git init -q "$ALL_REPO"
write_skill "$ALL_REPO/agents/skills/valid" "valid" "Use when testing all valid skills."
expect_success "--all scans the shared agents source tree" run_from "$ALL_REPO" "$VALIDATOR" --all

write_skill "$ALL_REPO/agents/skills/bad--name" "bad--name" "Use when testing an invalid tree."
expect_failure "--all fails when any shared skill is invalid" run_from "$ALL_REPO" "$VALIDATOR" --all

INSTALLED_REPO="$TEST_ROOT/installed-repo"
mkdir -p "$INSTALLED_REPO/.agents/skills"
git init -q "$INSTALLED_REPO"
write_skill "$INSTALLED_REPO/.agents/skills/valid" "valid" "Use when testing a project-installed skill."
expect_success "--all scans a project-installed .agents tree" run_from "$INSTALLED_REPO" "$VALIDATOR" --all

EMPTY_REPO="$TEST_ROOT/empty-repo"
mkdir -p "$EMPTY_REPO/agents/skills"
git init -q "$EMPTY_REPO"
expect_failure "--all rejects an empty selected skill root" run_from "$EMPTY_REPO" "$VALIDATOR" --all

FALLBACK_REPO="$TEST_ROOT/fallback-repo"
FALLBACK_SKILLS="$TEST_ROOT/personal-skills"
mkdir -p "$FALLBACK_REPO" "$FALLBACK_SKILLS/writing-skills/scripts"
git init -q "$FALLBACK_REPO"
cp "$VALIDATOR" "$FALLBACK_SKILLS/writing-skills/scripts/check-skill.sh"
write_skill "$FALLBACK_SKILLS/writing-skills" "writing-skills" "Use when testing validator-relative discovery."
write_skill "$FALLBACK_SKILLS/valid" "valid" "Use when testing a personal skill."
expect_success "--all falls back to the validator's sibling skill root" \
  run_from "$FALLBACK_REPO" "$FALLBACK_SKILLS/writing-skills/scripts/check-skill.sh" --all

printf '\n%s passed; %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
