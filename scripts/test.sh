#!/usr/bin/env bash
# Smoke-test harness for /list-skills v4.
#
# Runs the bash logic from list-skills.md against the real installed skills
# + various env conditions, then asserts expected output snippets via grep.
#
# Usage:
#   bash scripts/test.sh                          # repo dev mode (auto-detects ../commands/list-skills.md)
#   bash scripts/test.sh /path/to/list-skills.md  # explicit path
#
# Exit code: 0 if all cases pass, 1 if any fail.

set -u

# Locate list-skills.md: explicit arg > sibling commands/ dir > installed copy.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${1:-}" ] && [ -f "$1" ]; then
  LS_MD="$1"
elif [ -f "$SCRIPT_DIR/../commands/list-skills.md" ]; then
  LS_MD="$SCRIPT_DIR/../commands/list-skills.md"
else
  LS_MD="$HOME/.claude/commands/list-skills.md"
fi
if [ ! -f "$LS_MD" ]; then
  echo "FAIL: cannot find $LS_MD"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

LS_SH="$TMP/list-skills.sh"
awk '/^```bash$/{p=1;next} /^```$/{p=0} p' "$LS_MD" > "$LS_SH"
chmod +x "$LS_SH"

if [ ! -s "$LS_SH" ]; then
  echo "FAIL: extracted bash block is empty"
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=""

# ── Test runner ──────────────────────────────────────────────────────
# run_case <name> <expected-grep-pattern> <args...>
# Sets STDIN to /dev/null. Inherits env from caller (so env overrides work).
run_case() {
  local name="$1"
  local pattern="$2"
  shift 2
  local out
  out=$(bash "$LS_SH" "$@" 2>&1)
  if printf '%s' "$out" | grep -qE "$pattern"; then
    printf '  ✓ %s\n' "$name"
    PASS=$((PASS+1))
  else
    printf '  ✗ %s\n     pattern: %s\n' "$name" "$pattern"
    FAIL=$((FAIL+1))
    FAILED_CASES="${FAILED_CASES}${name}\n"
  fi
}

# run_case_neg <name> <forbidden-grep-pattern> <args...>
# Pass if pattern is NOT present.
run_case_neg() {
  local name="$1"
  local pattern="$2"
  shift 2
  local out
  out=$(bash "$LS_SH" "$@" 2>&1)
  if printf '%s' "$out" | grep -qE "$pattern"; then
    printf '  ✗ %s\n     forbidden pattern matched: %s\n' "$name" "$pattern"
    FAIL=$((FAIL+1))
    FAILED_CASES="${FAILED_CASES}${name}\n"
  else
    printf '  ✓ %s\n' "$name"
    PASS=$((PASS+1))
  fi
}

# ── Cases ────────────────────────────────────────────────────────────

echo "Running smoke tests for /list-skills v4..."
echo

# 5: Filter argument narrows output
run_case "filter narrows results" "Filtered by \"vercel\"" vercel
run_case "filter shows only vercel matches in headers/bullets" "vercel" vercel

# 6: No-match banner
run_case "no-match banner appears" "No skills matched filter" xyz999nonexistent_zzz

# 10: Intent grouping renders with H2 headers and emoji
run_case "intent header: shipping" "## 🚀 Shipping & deploying"
run_case "intent header: design" "## 🎨 Design & UX"
run_case "intent header: planning" "## 📋 Planning & strategy"

# Intent placement spot-checks: known skills land in expected buckets.
# We run unfiltered output once and grep for skill→bucket co-occurrence.
FULL_OUT=$(bash "$LS_SH" 2>&1)

check_in_section() {
  local name="$1"
  local section_emoji="$2"
  local section_label="$3"
  # Find the section header, then check that the skill bullet appears before the next ##
  if printf '%s' "$FULL_OUT" \
      | awk -v s="## ${section_emoji} ${section_label}" -v n="/${name}\`" '
          $0 ~ s {found=1; next}
          found && /^## / {found=0}
          found && index($0, n) > 0 {print "HIT"; exit}
        ' \
      | grep -q HIT; then
    printf '  ✓ /%s in %s\n' "$name" "$section_label"
    PASS=$((PASS+1))
  else
    printf '  ✗ /%s NOT found in %s section\n' "$name" "$section_label"
    FAIL=$((FAIL+1))
    FAILED_CASES="${FAILED_CASES}placement: /${name} → ${section_label}\n"
  fi
}

check_in_section "ship" "🚀" "Shipping & deploying"
check_in_section "investigate" "🔍" "Debugging & QA"
check_in_section "design-review" "🎨" "Design & UX"
check_in_section "office-hours" "📋" "Planning & strategy"
check_in_section "ai-sdk" "🤖" "AI & integrations"

# 9: Plugin dedup — caveman should appear with (via: ...) suffix
run_case "plugin dedup: caveman has via-list" "/caveman\`.*\(via:.*\)" caveman

# 9 (negative): caveman should NOT appear 4+ times in output
CAVEMAN_COUNT=$(printf '%s' "$FULL_OUT" | grep -c '/caveman`' 2>/dev/null || echo 0)
if [ "$CAVEMAN_COUNT" -lt 3 ]; then
  printf '  ✓ plugin dedup collapsed caveman duplicates (saw %d)\n' "$CAVEMAN_COUNT"
  PASS=$((PASS+1))
else
  printf '  ✗ plugin dedup did not collapse caveman duplicates (saw %d, expected <3)\n' "$CAVEMAN_COUNT"
  FAIL=$((FAIL+1))
  FAILED_CASES="${FAILED_CASES}plugin dedup: caveman count\n"
fi

# 12: Trigger chips appear for skills with "Use when..." pattern
run_case "trigger chip appears for /ship-like skill" "Use when:.*ship" ship

# 1-4: Branch awareness — we can't easily mock git inside this script without
# spawning a subshell with a fake repo. Instead, check the current branch
# behavior: if we're on a recognized verb branch, suggestion line should appear.
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
CURRENT_VERB="${CURRENT_BRANCH%%/*}"
case "$CURRENT_VERB" in
  design|fix|bugfix|hotfix|feat|feature|content|refactor)
    run_case "branch awareness: suggestion line on '$CURRENT_VERB' branch" "On \`$CURRENT_BRANCH\`"
    ;;
  *)
    run_case_neg "branch awareness: no suggestion on unknown verb '$CURRENT_VERB'" "you might want:"
    ;;
esac

# 7: Telemetry missing — temporarily move the file aside if it exists
TEL="$HOME/.gstack/analytics/skill-usage.jsonl"
if [ -f "$TEL" ]; then
  mv "$TEL" "$TEL.test-bak"
  run_case_neg "telemetry missing: no Recently used line" "Recently used:"
  mv "$TEL.test-bak" "$TEL"
else
  printf '  - skipped: telemetry missing test (no telemetry file to remove)\n'
fi

# 8: Telemetry malformed — append a corrupt line, expect output to still render
if [ -f "$TEL" ]; then
  cp "$TEL" "$TEL.test-bak"
  printf 'this is not json at all\n{"skill":"ship","ts":"not-a-date"}\n' >> "$TEL"
  run_case "telemetry malformed: output renders without error" "^# Skills"
  mv "$TEL.test-bak" "$TEL"
fi

# Header invariants
run_case "header: total count line" "^# Skills · [0-9]+ total"
run_case "header: emoji rendered (not literal)" "^## 🚀"

# ── Summary ──────────────────────────────────────────────────────────
echo
echo "─────────────────────────────────"
printf 'PASS: %d   FAIL: %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "Failed cases:"
  printf '%b' "$FAILED_CASES" | sed 's/^/  - /'
  exit 1
fi
exit 0
