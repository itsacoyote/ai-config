#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
INSTALLER="$ROOT/.agents/scripts/install-pwt.sh"
SOURCE="$ROOT/.agents/scripts/pwt"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/install-pwt-test.XXXXXX")
TMP=$(CDPATH= cd -- "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
passed=0
failed=0

ok() { printf 'ok - %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'not ok - %s\n' "$1"; failed=$((failed + 1)); }
run_test() { local name=$1; shift; if "$@"; then ok "$name"; else fail "$name"; fi; }

installs_stable_link() {
  local bin="$TMP/install/bin"
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >"$TMP/install.out"
  test -L "$bin/pwt" && test "$(readlink "$bin/pwt")" = "$SOURCE" && grep -q '^LINK ' "$TMP/install.out"
}

idempotent_install() {
  local bin="$TMP/idempotent/bin"
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >/dev/null
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >"$TMP/idempotent.out"
  test "$(readlink "$bin/pwt")" = "$SOURCE" && grep -q 'no changes' "$TMP/idempotent.out"
}

dry_run_does_not_write() {
  local bin="$TMP/dry/bin"
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" --dry-run >"$TMP/dry.out"
  test ! -e "$bin" && grep -q '^LINK ' "$TMP/dry.out"
}

migrates_identical_copy() {
  local bin="$TMP/migrate/bin" backup
  mkdir -p "$bin"; cp "$SOURCE" "$bin/pwt"
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >"$TMP/migrate.out"
  backup=$(awk '/^BACKUP / { print $2 }' "$TMP/migrate.out")
  test -L "$bin/pwt" && test "$(readlink "$bin/pwt")" = "$SOURCE" &&
    grep -q '^MIGRATE ' "$TMP/migrate.out" && test -f "$backup" && cmp -s "$SOURCE" "$backup"
}

refuses_different_regular_file() {
  local bin="$TMP/conflict/bin"
  mkdir -p "$bin"; printf '#!/bin/sh\nprintf local\\n\n' >"$bin/pwt"; chmod +x "$bin/pwt"
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >"$TMP/conflict.out" 2>"$TMP/conflict.err" &&
    grep -q 'different regular file' "$TMP/conflict.err" && grep -q 'local' "$bin/pwt" && test ! -L "$bin/pwt"
}

relinks_only_with_explicit_option() {
  local bin="$TMP/relink/bin" other="$TMP/other-pwt" backup
  mkdir -p "$bin"; printf '#!/bin/sh\n' >"$other"; chmod +x "$other"; ln -s "$other" "$bin/pwt"
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >/dev/null 2>"$TMP/relink.err" || return 1
  test "$(readlink "$bin/pwt")" = "$other" || return 1
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" --replace-link >"$TMP/relink.out"
  backup=$(awk '/^BACKUP / { print $2 }' "$TMP/relink.out")
  test "$(readlink "$bin/pwt")" = "$SOURCE" && grep -q '^RELINK ' "$TMP/relink.out" &&
    test -L "$backup" && test "$(readlink "$backup")" = "$other"
}

preserves_unrelated_files() {
  local bin="$TMP/unrelated/bin"
  mkdir -p "$bin"; printf 'keep\n' >"$bin/other-tool"
  "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >/dev/null
  grep -q '^keep$' "$bin/other-tool"
}

rejects_unsafe_paths_and_source() {
  local real="$TMP/real-bin" linked="$TMP/linked-bin" bad_source="$TMP/bad-pwt"
  mkdir -p "$real"; ln -s "$real" "$linked"
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$linked" >/dev/null 2>"$TMP/linked.err" &&
    grep -Eqi '(unsafe|non-directory)' "$TMP/linked.err" || return 1

  cp "$SOURCE" "$bad_source"; chmod 0644 "$bad_source"
  ! "$INSTALLER" --source "$bad_source" --bin-dir "$TMP/nonexec/bin" >/dev/null 2>"$TMP/nonexec.err" &&
    grep -qi 'not executable' "$TMP/nonexec.err" || return 1

  rm "$bad_source"; ln -s "$SOURCE" "$bad_source"
  ! "$INSTALLER" --source "$bad_source" --bin-dir "$TMP/source-link/bin" >/dev/null 2>"$TMP/source-link.err" &&
    grep -Eqi '(safely open|symbolic|symlink)' "$TMP/source-link.err"
}

refuses_unsafe_bin_permissions() {
  local bin="$TMP/writable-bin" sticky="$TMP/sticky-bin"
  mkdir -p "$bin" "$sticky"; chmod 0777 "$bin"; chmod 1777 "$sticky"
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >/dev/null 2>"$TMP/writable.err" &&
    grep -qi 'unsafe ownership or permissions' "$TMP/writable.err" && test ! -e "$bin/pwt" || return 1
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$sticky" >/dev/null 2>"$TMP/sticky.err" &&
    grep -qi 'unsafe ownership or permissions' "$TMP/sticky.err" && test ! -e "$sticky/pwt"
}

refuses_source_equal_to_destination() {
  local bin="$TMP/self/bin"
  mkdir -p "$bin"; cp "$SOURCE" "$bin/pwt"
  ! "$INSTALLER" --source "$bin/pwt" --bin-dir "$bin" >/dev/null 2>"$TMP/self.err" &&
    grep -qi 'source and destination must differ' "$TMP/self.err" &&
    test -f "$bin/pwt" && test ! -L "$bin/pwt" && test -x "$bin/pwt" && cmp -s "$SOURCE" "$bin/pwt"
}

refuses_case_variant_same_destination() {
  local bin="$TMP/case-self/bin"
  mkdir -p "$bin"; cp "$SOURCE" "$bin/PWT"
  if [[ ! -e "$bin/pwt" ]]; then
    return 0
  fi
  ! "$INSTALLER" --source "$bin/PWT" --bin-dir "$bin" >/dev/null 2>"$TMP/case-self.err" &&
    grep -qi 'source and destination must differ' "$TMP/case-self.err" &&
    test -f "$bin/PWT" && test ! -L "$bin/PWT" && cmp -s "$SOURCE" "$bin/PWT"
}

filesystem_errors_do_not_show_tracebacks() {
  local bin="$TMP/read-only-bin"
  mkdir -p "$bin"; chmod 0555 "$bin"
  ! "$INSTALLER" --source "$SOURCE" --bin-dir "$bin" >/dev/null 2>"$TMP/read-only.err" &&
    grep -qi 'install-pwt:' "$TMP/read-only.err" && ! grep -q 'Traceback' "$TMP/read-only.err" &&
    test ! -e "$bin/pwt" || return 1

  ! "$INSTALLER" --source '~ai-config-no-such-user/pwt' --bin-dir "$TMP/bad-path/bin" \
    >/dev/null 2>"$TMP/bad-path.err" &&
    grep -qi 'invalid source or bin directory path' "$TMP/bad-path.err" &&
    ! grep -q 'Traceback' "$TMP/bad-path.err"
}

manifest_covers_installer() {
  python3 -I - "$ROOT" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / ".agents/manifest.json").read_text())
owned = set(manifest["ownership"]["files"])
checksums = set(manifest["ownership"]["checksums"])
required = {
    ".agents/scripts/install-pwt.sh",
    ".agents/scripts/tests/install-pwt-test.sh",
}
raise SystemExit(0 if required <= owned and required <= checksums else 1)
PY
}

run_test 'installs a stable launcher symlink' installs_stable_link
run_test 'repeated installation is idempotent' idempotent_install
run_test 'dry run reports without creating directories' dry_run_does_not_write
run_test 'identical copied launcher is safely migrated' migrates_identical_copy
run_test 'different regular file is preserved' refuses_different_regular_file
run_test 'different symlink requires explicit replacement' relinks_only_with_explicit_option
run_test 'unrelated bin directory files are preserved' preserves_unrelated_files
run_test 'symlinked paths and unsafe launcher sources are rejected' rejects_unsafe_paths_and_source
run_test 'group- or world-writable bin directory is rejected' refuses_unsafe_bin_permissions
run_test 'source equal to destination is rejected without data loss' refuses_source_equal_to_destination
run_test 'case-variant same destination is rejected when applicable' refuses_case_variant_same_destination
run_test 'filesystem errors fail cleanly without tracebacks' filesystem_errors_do_not_show_tracebacks
run_test 'manifest covers pwt installer and tests' manifest_covers_installer

printf '%s passed; %s failed\n' "$passed" "$failed"
test "$failed" -eq 0
