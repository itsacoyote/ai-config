#!/usr/bin/env bash
# repository-contract-test.sh — shared Agent Skills layout and documentation contracts

set -u

pass=0
fail=0

ok()     { pass=$((pass + 1)); printf '  ok   - %s\n' "$1"; }
not_ok() { fail=$((fail + 1)); printf '  FAIL - %s\n' "$1"; }

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="${REPO_ROOT_UNDER_TEST:-$(CDPATH= cd "$SCRIPT_DIR/../../.." && pwd -P)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agents-contract-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

ACTIVE_DOCS="
$REPO_ROOT/README.md
$REPO_ROOT/AGENTS.md
$REPO_ROOT/agents/README.md
$REPO_ROOT/codex/README.md
$REPO_ROOT/codex/AGENTS.md
$REPO_ROOT/docs/decisions/0010-shared-agent-skills-library.md
"

LINK_DOCS="$ACTIVE_DOCS
$REPO_ROOT/docs/decisions/0006-per-harness-config-trees.md
$REPO_ROOT/docs/decisions/0008-pi-global-only-config.md
"

docs_exist=1
printf '%s' "$LINK_DOCS" | while IFS= read -r file; do
  [ -n "$file" ] || continue
  if [ ! -f "$file" ]; then
    printf 'missing required documentation: %s\n' "$file" >&2
    exit 1
  fi
done || docs_exist=0
if [ "$docs_exist" -eq 1 ]; then
  ok 'every audited documentation file exists'
else
  not_ok 'every audited documentation file exists'
fi

find "$REPO_ROOT/agents/skills" -mindepth 1 -maxdepth 1 -type d -print |
  sed "s|^$REPO_ROOT/agents/skills/||" | sort >"$TMP/actual-skills"
printf '%s\n' branch-names create-pr git-commit writing-skills >"$TMP/expected-skills"
if cmp -s "$TMP/expected-skills" "$TMP/actual-skills"; then
  ok 'canonical tree contains exactly the four shared skills'
else
  not_ok 'canonical tree contains exactly the four shared skills'
  diff -u "$TMP/expected-skills" "$TMP/actual-skills" 2>/dev/null || true
fi

if [ ! -e "$REPO_ROOT/codex/.agents/skills" ]; then
  ok 'retired codex skill source is absent'
else
  not_ok 'retired codex skill source is absent'
fi

names_match=1
for skill_dir in "$REPO_ROOT/agents/skills"/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(sed -n 's/^name:[[:space:]]*//p' "$skill_dir/SKILL.md" | head -1)"
  [ "$skill_name" = "$(basename "$skill_dir")" ] || names_match=0
done
if [ "$names_match" -eq 1 ]; then
  ok 'every shared skill frontmatter name matches its directory'
else
  not_ok 'every shared skill frontmatter name matches its directory'
fi

if printf '%s' "$ACTIVE_DOCS" | (
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    grep -nE 'codex/\.agents/skills' "$file" && exit 0
  done
  exit 1
); then
  not_ok 'active documentation contains no retired Codex source path'
else
  ok 'active documentation contains no retired Codex source path'
fi

if printf '%s' "$ACTIVE_DOCS" | (
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    grep -nE 'cp[[:space:]]+[^[:space:]]*AGENTS\.md' "$file" && exit 0
  done
  exit 1
); then
  not_ok 'installer documentation contains no AGENTS.md copy command'
else
  ok 'installer documentation contains no AGENTS.md copy command'
fi

AGENTS_README="$REPO_ROOT/agents/README.md"
if [ -f "$AGENTS_README" ] && grep -Fq 'agents/skills/' "$AGENTS_README" && \
  grep -Fq 'harness-specific configuration under `codex/` or `pi/`' "$AGENTS_README" && \
  grep -Fq 'personal additive install' "$AGENTS_README" && \
  grep -Fq 'yourself from the repository checkout' "$AGENTS_README" && \
  grep -Fq 'never reads, installs, merges, or modifies `AGENTS.md`, `~/.codex`, or Pi configuration' "$AGENTS_README"; then
  ok 'agents README documents shared authorship and manual install boundaries'
else
  not_ok 'agents README documents shared authorship and manual install boundaries'
fi

AUTHORING_REF="$REPO_ROOT/agents/skills/writing-skills/references/agent-skills-authoring.md"
if grep -Fq 'Codex and Pi capability matrix' "$AUTHORING_REF" && \
  grep -Fq '.agents/skills' "$AUTHORING_REF" && grep -Fq '~/.agents/skills' "$AUTHORING_REF" && \
  grep -Fq '$skill-name' "$AUTHORING_REF" && grep -Fq '/skill:name' "$AUTHORING_REF"; then
  ok 'portable guidance documents Codex and Pi discovery and invocation'
else
  not_ok 'portable guidance documents Codex and Pi discovery and invocation'
fi

MAIN_SKILL="$REPO_ROOT/agents/skills/writing-skills/SKILL.md"
if ! grep -Fq '/skill:name' "$MAIN_SKILL" && ! grep -Fq '| Explicit |' "$MAIN_SKILL"; then
  ok 'client-specific invocation details live only in the authoring reference'
else
  not_ok 'client-specific invocation details live only in the authoring reference'
fi

if grep -Fq 'skills-ref validate <target-skill-dir>' "$MAIN_SKILL"; then
  ok 'optional standard validation uses the actual target skill path'
else
  not_ok 'optional standard validation uses the actual target skill path'
fi

ADR="$REPO_ROOT/docs/decisions/0010-shared-agent-skills-library.md"
if grep -Fq 'feat/pi-skills' "$ADR" && grep -Fq 'portable skills move to `agents/skills/`' "$ADR" && \
  grep -Fq 'Pi-only skills and configuration stay under `pi/`' "$ADR"; then
  ok 'Pi port landing order and destination split are explicit'
else
  not_ok 'Pi port landing order and destination split are explicit'
fi

links_ok=1
printf '%s' "$LINK_DOCS" | while IFS= read -r source_md; do
  [ -n "$source_md" ] || continue
  [ -f "$source_md" ] || continue
  grep -oE '\]\([^)]+\)' "$source_md" 2>/dev/null |
    sed 's/^](//; s/)$//' >"$TMP/links" || true
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
      /*) path="$REPO_ROOT/${target#/}" ;;
      *) path="$(dirname "$source_md")/$target" ;;
    esac
    if [ ! -e "$path" ]; then
      printf 'dead link: %s: %s\n' "$source_md" "$link" >&2
      exit 1
    fi
  done <"$TMP/links"
done || links_ok=0
if [ "$links_ok" -eq 1 ]; then
  ok 'active documentation relative links resolve'
else
  not_ok 'active documentation relative links resolve'
fi

printf '\nresults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
