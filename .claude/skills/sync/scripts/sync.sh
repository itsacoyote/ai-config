#!/bin/sh
# sync.sh — bring the local checkout up to date with main before feature work.
#
# Encodes the deterministic mechanics of the `sync` skill: preflight, branch
# switch + fast-forward pull, change summary, and detection-driven environment
# refresh (package managers → migrations → .env diff → Docker → project-specific
# steps). The two human decisions stay with the caller and arrive as flags:
#   • dirty working tree  → pass --stash to stash it (otherwise the run stops)
#   • which deps to install → pass --install all|<csv> (default: none, recommend only)
#
# Run --dry-run first (read-only: no stash/switch/pull/install) to see the dirty
# state and detected ecosystems, decide the two questions, then run for real.
#
# Hard safety constraints (never violated): never commit; never reset/clean/
# checkout-discard; never auto-apply migrations; never modify .env; never run
# docker compose pull/build; never retry a failed --ff-only pull; origin + the
# detected main branch only.
#
# Usage:
#   sync.sh --dry-run                 preview everything, mutate nothing
#   sync.sh                           clean tree → switch+pull+summary; deps recommended only
#   sync.sh --stash                   stash a dirty tree first, then sync
#   sync.sh --install all             also run every detected ecosystem's install
#   sync.sh --install npm,bundler     run installs only for these detected tools
#   sync.sh --main develop            override the detected main branch
#
# Exit: 0 ok; 1 fatal (dirty without --stash, failed pull/install, not a repo); 2 usage.

set -u

DRY=0
STASH=0
INSTALL="none"
MAIN_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --stash)   STASH=1; shift ;;
    --install) [ $# -ge 2 ] || { echo "error: --install needs a value (all|none|csv)" >&2; exit 2; }; INSTALL="$2"; shift 2 ;;
    --main)    [ $# -ge 2 ] || { echo "error: --main needs a branch" >&2; exit 2; }; MAIN_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { echo "✗ $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── Preflight ────────────────────────────────────────────────────────────────
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  die "Not inside a git repository. Navigate to a git repo root and rerun /sync."
cd "$(git rev-parse --show-toplevel)"

# Detect main branch: init.defaultBranch → origin/HEAD → main (per skill).
if [ -n "$MAIN_OVERRIDE" ]; then
  MAIN="$MAIN_OVERRIDE"
else
  MAIN="$(git config init.defaultBranch 2>/dev/null || true)"
  if [ -z "$MAIN" ]; then
    MAIN="$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  fi
  [ -n "$MAIN" ] || MAIN="main"
fi
PREV="$(git branch --show-current 2>/dev/null)"; [ -n "$PREV" ] || PREV="(detached HEAD)"

echo "Detected main branch: $MAIN"
echo "Current branch: $PREV"

DIRTY="$(git status --porcelain)"
STASH_REF=""
if [ -n "$DIRTY" ]; then
  echo
  echo "Working tree has uncommitted changes:"
  printf '%s\n' "$DIRTY" | sed 's/^/  /'
  if [ "$DRY" = 1 ]; then
    echo "(dry-run) decide: re-run with --stash to stash these, or commit/discard them yourself."
  elif [ "$STASH" = 1 ]; then
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    STASH_REF="$(git stash push -u -m "sync: auto-stash $ts" 2>&1)" || die "git stash failed:
$STASH_REF"
    echo "Stashed: $STASH_REF"
  else
    die "Dirty working tree. Re-run with --stash to stash and continue, or commit/discard the changes yourself (nothing was changed)."
  fi
fi

# ── Branch switch + fast-forward pull ────────────────────────────────────────
PRE_SHA=""; POST_SHA=""; NEW_COMMITS=""
if [ "$DRY" = 1 ]; then
  echo
  echo "(dry-run) would: git switch $MAIN && git fetch origin && git pull --ff-only origin $MAIN"
else
  git switch "$MAIN" || die "git switch $MAIN failed (see stderr above)."
  PRE_SHA="$(git rev-parse "$MAIN")"
  git fetch origin || die "git fetch origin failed (see stderr above)."
  git pull --ff-only origin "$MAIN" || die "git pull --ff-only origin $MAIN failed — left unchanged. Resolve manually (no --rebase/--no-ff retry)."
  POST_SHA="$(git rev-parse HEAD)"
  NEW_COMMITS="$(git log --oneline --no-merges "$PRE_SHA"..HEAD 2>/dev/null)"
fi

# ── Detection helpers ────────────────────────────────────────────────────────
# JS manager + runner: package.json "packageManager" field wins, else lockfile.
JS_MGR=""; JS_RUNNER="npx"
if [ -f package.json ]; then
  pm="$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([a-z]*\)@.*/\1/p' package.json | head -1)"
  case "$pm" in
    bun)  JS_MGR=bun;  JS_RUNNER=bunx ;;
    pnpm) JS_MGR=pnpm; JS_RUNNER="pnpm dlx" ;;
    yarn) JS_MGR=yarn; JS_RUNNER=yarn ;;
    npm)  JS_MGR=npm;  JS_RUNNER=npx ;;
  esac
fi
if [ -z "$JS_MGR" ]; then
  if   [ -f bun.lockb ] || [ -f bun.lock ]; then JS_MGR=bun;  JS_RUNNER=bunx
  elif [ -f pnpm-lock.yaml ];               then JS_MGR=pnpm; JS_RUNNER="pnpm dlx"
  elif [ -f yarn.lock ];                    then JS_MGR=yarn; JS_RUNNER=yarn
  elif [ -f package-lock.json ];            then JS_MGR=npm;  JS_RUNNER=npx
  fi
fi

# install command for a JS manager token
js_install_cmd() {
  case "$1" in
    bun)  echo "bun install" ;;
    pnpm) echo "pnpm install --frozen-lockfile" ;;
    yarn) echo "yarn install --frozen-lockfile" ;;
    npm)  echo "npm install" ;;
  esac
}

# Build the list of detected ecosystems as "token|command|binary" lines.
ECOS="$(
  [ -n "$JS_MGR" ] && echo "$JS_MGR|$(js_install_cmd "$JS_MGR")|$JS_MGR"
  [ -f Gemfile.lock ]   && echo "bundler|bundle install|bundle"
  # Python precedence: uv → poetry → pipenv (only the winner installs)
  if   [ -f uv.lock ];      then echo "uv|uv sync|uv"
  elif [ -f poetry.lock ];  then echo "poetry|poetry install|poetry"
  elif [ -f Pipfile.lock ]; then echo "pipenv|pipenv install|pipenv"
  fi
  [ -f go.mod ]         && echo "go|go mod download|go"
  [ -f Cargo.lock ]     && echo "cargo|cargo fetch|cargo"
  [ -f composer.lock ]  && echo "composer|composer install|composer"
  [ -f mix.lock ]       && echo "mix|mix deps.get|mix"
)"

want_install() {  # $1 = token
  case "$INSTALL" in
    all) return 0 ;;
    none|"") return 1 ;;
    *) case ",$INSTALL," in *,"$1",*) return 0 ;; *) return 1 ;; esac ;;
  esac
}

sec() { echo; echo "── $1 ──"; }

# ── Environment refresh: package managers ────────────────────────────────────
sec "Dependencies"
DEP_REPORT=""
if [ -z "$ECOS" ]; then
  echo "No package-manager lockfiles detected."
else
  printf '%s\n' "$ECOS" | while IFS='|' read -r tok cmd bin; do
    [ -n "$tok" ] || continue
    if ! have "$bin"; then
      echo "$tok: not installed (skipped) — \`$cmd\`"
    elif [ "$DRY" = 1 ]; then
      echo "$tok: detected — \`$cmd\` (run: --install $tok, or --install all)"
    elif want_install "$tok"; then
      echo "$tok: running \`$cmd\` ..."
      if sh -c "$cmd"; then echo "$tok: ran"; else echo "$tok: FAILED" >&2; exit 1; fi
    else
      echo "$tok: skipped — \`$cmd\` (re-run with --install $tok to run)"
    fi
  done || die "an install failed — see output above."
fi
# pip / pyproject are surfaced only, never run.
[ -f requirements.txt ] && echo "pip: surfaced only — run \`pip install -r requirements.txt\` in your active environment if needed"
if [ -f pyproject.toml ] && [ ! -f uv.lock ] && [ ! -f poetry.lock ] && [ ! -f Pipfile.lock ]; then
  echo "pyproject.toml detected without a recognized lockfile — run the appropriate install manually"
fi

# ── Environment refresh: migrations (recommend only) ─────────────────────────
sec "Migrations to consider (none are run)"
mig=0
mig_line() { echo "Pending migrations may exist — run \`$1\` if needed"; mig=1; }
{ [ -f bin/rails ] || [ -f config/application.rb ]; } && mig_line "bin/rails db:migrate"
[ -f alembic.ini ]            && mig_line "alembic upgrade head"
[ -f prisma/schema.prisma ]   && mig_line "$JS_RUNNER prisma migrate deploy"
{ [ -f flyway.conf ] || [ -d flyway ]; } && mig_line "flyway migrate"
if [ -f manage.py ] && grep -riqs django requirements*.txt Pipfile pyproject.toml 2>/dev/null; then
  mig_line "python manage.py migrate"
fi
{ [ -f knexfile.js ] || [ -f knexfile.ts ]; }       && mig_line "$JS_RUNNER knex migrate:latest"
{ [ -f drizzle.config.ts ] || [ -f drizzle.config.js ]; } && mig_line "$JS_RUNNER drizzle-kit migrate"
[ -d supabase/migrations ]    && mig_line "supabase db push (or $JS_RUNNER supabase db push)"
[ "$mig" = 0 ] && echo "No migration tooling detected."

# ── Environment refresh: .env diff (keys only; values never read) ────────────
sec "Environment variables"
EXAMPLE=""
for f in .env.example .env.sample .env.template; do [ -f "$f" ] && { EXAMPLE="$f"; break; }; done
if [ -z "$EXAMPLE" ]; then
  echo "No .env example file detected."
elif [ ! -f .env ]; then
  echo "No local .env found — copy $EXAMPLE to .env and fill in values."
else
  keys_of() { grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$1" 2>/dev/null | sed 's/[[:space:]]*=//; s/^[[:space:]]*//' | sort -u; }
  env_keys="$(keys_of .env)"
  missing=""
  for k in $(keys_of "$EXAMPLE"); do
    printf '%s\n' "$env_keys" | grep -qxF "$k" || missing="${missing:+$missing
}$k"
  done
  if [ -n "$missing" ]; then
    echo "Keys in $EXAMPLE missing from .env:"
    printf '%s\n' "$missing" | sed 's/^/  /'
  else
    echo "All keys present."
  fi
fi

# ── Environment refresh: Docker (warn only; never pull/build) ────────────────
sec "Docker"
compose="$(find . -maxdepth 2 \( -name docker-compose.yml -o -name docker-compose.yaml -o -name compose.yml -o -name compose.yaml \) 2>/dev/null | head -1)"
if [ -n "$compose" ]; then
  echo "Compose detected ($compose) — local images may be stale. Run \`docker compose pull\`"
  echo "and \`docker compose build\` if your stack expects current upstream images."
else
  echo "No compose file detected."
fi

# ── Project-specific sync steps (surfaced verbatim; never executed) ──────────
sec "Project-specific steps"
found_proj=0
for f in CLAUDE.md AGENTS.md .cursorrules .windsurfrules; do
  [ -f "$f" ] || continue
  block="$(awk '
    /^#+[[:space:]]*([Ss][Yy][Nn][Cc]|[Pp]ost-pull|[Aa]fter [Pp]ulling|[Bb]ootstrap)([[:space:]].*)?$/ { grab=1; print FILENAME": "$0; next }
    grab && /^#/ { grab=0 }
    grab { print }
  ' "$f")"
  [ -n "$block" ] && { printf '%s\n' "$block"; found_proj=1; }
done
[ "$found_proj" = 0 ] && echo "No project-specific sync steps found in CLAUDE.md, AGENTS.md, .cursorrules, or .windsurfrules."

# ── Branch state + change summary ────────────────────────────────────────────
sec "Branch state"
if [ "$DRY" = 1 ]; then
  echo "(dry-run) on $PREV; would switch to $MAIN and fast-forward. Nothing was changed."
  [ -n "$STASH_REF" ] && echo "$STASH_REF"
else
  echo "$PREV → $MAIN"
  echo "$PRE_SHA → $POST_SHA"
  [ -n "$STASH_REF" ] && { echo "Stashed uncommitted changes as: $STASH_REF"; echo "Recover with: git stash pop"; }
  sec "Recent commits"
  if [ -z "$NEW_COMMITS" ]; then
    echo "main is already up to date — no new commits since last sync."
  else
    n="$(printf '%s\n' "$NEW_COMMITS" | wc -l | tr -d ' ')"
    printf '%s\n' "$NEW_COMMITS" | head -20
    [ "$n" -gt 20 ] && echo "+$((n - 20)) more"
  fi
  sec "Next step"
  echo "Ready to start. Create a new branch, or run \`git switch $PREV\` to return to your prior work."
fi

exit 0
