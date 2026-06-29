#!/bin/sh
# project-checks.sh — discover and run a project's mechanical quality gates.
#
# Encodes the deterministic part of the `project-checks` skill: detect the
# toolchain the project actually defines, then run the checks cheapest-first
# (format → lint → typecheck → spell → test), failing fast. It is
# NON-MUTATING — it runs checks in check mode and reports failures; it never
# auto-fixes. Auto-fix vs. surface, and DONE/BLOCKED reporting, stay in the
# skill (judgment).
#
# Discovery precedence per category (first hit wins, "only run what exists"):
#   1. package.json script   (JS/TS — package manager inferred from the lockfile)
#   2. Makefile target
#   3. Justfile target
#   4. language-native        (Rust / Go / Python)
#
# Usage:
#   project-checks.sh              discover, print the plan, run fail-fast
#   project-checks.sh --list       discover and print the plan only (no run)
#   project-checks.sh --keep-going run every check even after one fails
#
# Exit: 0 all passed (or nothing to run); 1 a check failed; 2 usage error.

set -u

LIST_ONLY=0
KEEP_GOING=0
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--list)       LIST_ONLY=1; shift ;;
    -k|--keep-going) KEEP_GOING=1; shift ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Run order, cheapest first.
CATEGORIES="format lint typecheck spell test"

# ── Toolchain probes ────────────────────────────────────────────────────────
node_pm() {
  if   [ -f pnpm-lock.yaml ]; then echo "pnpm run"
  elif [ -f yarn.lock ];      then echo "yarn"
  elif [ -f bun.lockb ];      then echo "bun run"
  else echo "npm run"
  fi
}

NODE_SCRIPTS=""
PM=""
if [ -f package.json ]; then
  PM="$(node_pm)"
  if command -v jq >/dev/null 2>&1; then
    NODE_SCRIPTS="$(jq -r '.scripts // {} | keys[]' package.json 2>/dev/null || true)"
  else
    echo "→ note: jq not found — cannot read package.json scripts; falling back to non-node checks only." >&2
  fi
fi

has_script()      { printf '%s\n' "$NODE_SCRIPTS" | grep -qxF "$1"; }
has_make_target() { [ -f Makefile ] && grep -qE "^$1:" Makefile 2>/dev/null; }
just_file()       { if [ -f Justfile ]; then echo Justfile; elif [ -f justfile ]; then echo justfile; fi; }
has_just_target() { jf="$(just_file)"; [ -n "$jf" ] && grep -qE "^$1:" "$jf" 2>/dev/null; }
is_python()       { [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; }
have()            { command -v "$1" >/dev/null 2>&1; }

# Echo "$PM <script>" for the first candidate script name that exists.
find_node() {
  [ -n "$NODE_SCRIPTS" ] || return 1
  for s in "$@"; do
    if has_script "$s"; then echo "$PM $s"; return 0; fi
  done
  return 1
}

# ── Per-category discovery (precedence: node → make → just → native) ─────────
disc_format() {
  c=$(find_node format:check fmt:check check:format format fmt prettier:check prettier) && { echo "$c"; return; }
  has_make_target fmt    && { echo "make fmt"; return; }
  has_make_target format && { echo "make format"; return; }
  has_just_target fmt    && { echo "just fmt"; return; }
  has_just_target format && { echo "just format"; return; }
  [ -f Cargo.toml ] && have cargo  && { echo "cargo fmt --check"; return; }
  [ -f go.mod ]     && have gofmt  && { echo "gofmt -l ."; return; }
  is_python         && have ruff   && { echo "ruff format --check ."; return; }
  is_python         && have black  && { echo "black --check ."; return; }
}

disc_lint() {
  c=$(find_node lint lint:check eslint) && { echo "$c"; return; }
  has_make_target lint && { echo "make lint"; return; }
  has_just_target lint && { echo "just lint"; return; }
  [ -f Cargo.toml ] && have cargo         && { echo "cargo clippy --quiet"; return; }
  [ -f go.mod ]     && have golangci-lint && { echo "golangci-lint run"; return; }
  [ -f go.mod ]     && have go            && { echo "go vet ./..."; return; }
  is_python         && have ruff          && { echo "ruff check ."; return; }
}

disc_typecheck() {
  c=$(find_node typecheck type-check check:types types tsc) && { echo "$c"; return; }
  has_make_target typecheck && { echo "make typecheck"; return; }
  has_just_target typecheck && { echo "just typecheck"; return; }
  is_python && have mypy && { echo "mypy ."; return; }
}

disc_spell() {
  c=$(find_node spell spell:check spellcheck cspell) && { echo "$c"; return; }
  has_make_target spell && { echo "make spell"; return; }
  has_just_target spell && { echo "just spell"; return; }
}

disc_test() {
  c=$(find_node test test:unit test:ci) && { echo "$c"; return; }
  has_make_target test && { echo "make test"; return; }
  has_just_target test && { echo "just test"; return; }
  [ -f Cargo.toml ] && have cargo && { echo "cargo test"; return; }
  [ -f go.mod ]     && have go    && { echo "go test ./..."; return; }
  is_python         && have pytest && { echo "pytest"; return; }
}

# ── Build the plan ──────────────────────────────────────────────────────────
PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT
for cat in $CATEGORIES; do
  cmd="$("disc_$cat")"
  [ -n "$cmd" ] && printf '%s\t%s\n' "$cat" "$cmd" >> "$PLAN"
done

if [ ! -s "$PLAN" ]; then
  echo "no project checks found — nothing to run (skip gracefully)."
  exit 0
fi

echo "Discovered checks (run order):"
while IFS="$(printf '\t')" read -r cat cmd; do
  printf '  • %-9s %s\n' "$cat" "$cmd"
done < "$PLAN"

# Informational: pre-commit bundles many of these but mutates, so it is not auto-run.
if [ -f .pre-commit-config.yaml ] && have pre-commit; then
  echo "  (pre-commit available: \`pre-commit run --all-files\` bundles hooks — not auto-run; it mutates)"
fi

if [ "$LIST_ONLY" = 1 ]; then
  exit 0
fi

# ── Run, fail-fast ──────────────────────────────────────────────────────────
status=0
ran=""
while IFS="$(printf '\t')" read -r cat cmd; do
  printf '\n▶ %s: %s\n' "$cat" "$cmd"
  if sh -c "$cmd"; then
    printf '✓ %s passed\n' "$cat"
    ran="$ran $cat"
  else
    rc=$?
    printf '✗ %s FAILED (exit %s)\n' "$cat" "$rc"
    status=1
    [ "$KEEP_GOING" = 1 ] || { echo "→ stopping (fail-fast); fix and re-run, or pass --keep-going."; break; }
  fi
done < "$PLAN"

echo
if [ "$status" = 0 ]; then
  echo "✓ all discovered checks passed."
else
  echo "✗ one or more checks failed — the task is not done. Fix (auto-fix where safe), then re-run."
fi
exit "$status"
