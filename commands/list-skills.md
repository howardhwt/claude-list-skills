---
description: List installed skills, grouped by intent, with branch-aware suggestions
allowed-tools: Bash
argument-hint: "[filter]"
---

You are listing every installed Claude Code skill as a discovery tool, not a directory listing.

## Output rules

1. Run the bash script below. It prints **native markdown** — real `##` headers, real `**bold**`, emoji icons, plain bullet lists.
2. **Do NOT wrap the output in a fenced code block.** Relay the bash stdout to the user as your response text directly so chat renders it as formatted markdown (real headers, real bold, real emoji).
3. Do not add any commentary above or below — the script is self-contained.
4. If a filter argument was passed and zero skills matched, the script prints a "No skills matched" line; pass that through unchanged.

## Bash

```bash
FILTER="$1"

# ── Data flow ────────────────────────────────────────────────────────
#
# /list-skills [filter]
#         │
#         ├─► branch_suggestion()  ─┐
#         ├─► recently_used_raw() ──┤  Header block
#         │                         │
#         ▼                         ▼
#  for each SKILL.md (3 scopes):
#    parse_skill -> name, desc
#    match($FILTER)
#    classify_intent -> bucket
#    plugin_dedup (plugin scope)
#         │
#         ▼
#  Group by intent bucket -> emit markdown (no fence)
#
# ─────────────────────────────────────────────────────────────────────

# === parse_skill: YAML frontmatter parser ===
parse_skill() {
  local file="$1"
  local fallback
  fallback=$(basename "$(dirname "$file")")
  awk -v fb="$fallback" '
    BEGIN { fm=0; in_block=0; name=""; desc="" }
    /^---[[:space:]]*$/ { if (fm == 0) { fm=1 } else { exit } next }
    fm == 0 { next }
    {
      if (in_block) {
        if (/^[A-Za-z_][A-Za-z0-9_-]*:/) { in_block = 0 }
        else { line=$0; sub(/^[[:space:]]+/, "", line); if (line!="") desc = (desc=="" ? line : desc " " line); next }
      }
      if (/^name:/) { line=$0; sub(/^name:[[:space:]]*/, "", line); gsub(/^"|"$|^'\''|'\''$/, "", line); name=line }
      else if (/^description:/) {
        line=$0; sub(/^description:[[:space:]]*/, "", line)
        if (line=="|" || line==">" || line=="|-" || line==">-" || line=="|+" || line==">+") { in_block=1; desc="" }
        else { gsub(/^"|"$|^'\''|'\''$/, "", line); desc=line }
      }
    }
    END {
      if (name=="") name=fb
      if (desc=="") desc="(no description)"
      gsub(/[[:space:]]+/, " ", desc); sub(/^ /, "", desc); sub(/ $/, "", desc)
      printf "%s\t%s\n", name, desc
    }' "$file"
}

# === classify_intent: name + desc -> bucket ===
classify_intent() {
  local name="$1"
  local desc="$2"

  # Explicit name mappings (highest precision). Order matters within a case branch.
  case "$name" in
    ship|land-and-deploy|canary|deploy|deployments-cicd|setup-deploy|next-upgrade|gstack-upgrade|release|document-release)
      echo "shipping"; return ;;
    investigate|qa|qa-only|browse|review|security-review|webapp-testing|systematic-debugging|verification|verification-before-completion)
      echo "debug"; return ;;
    design-html|design-review|design-shotgun|design-consultation|plan-design-review|vigglify|frontend-design|frontend-design:frontend-design|brand-guidelines|theme-factory|canvas-design|figma-*|shadcn|figma:*|slack-gif-creator)
      echo "design"; return ;;
    plan-*|office-hours|autoplan|drill|brainstorming|brainstorm|writing-plans|write-plan|executing-plans|execute-plan|writing-skills|skill-creator|receiving-code-review|requesting-code-review|superpowers:*)
      echo "planning"; return ;;
    doc-coauthoring|internal-comms|retro|learn|context-save|context-restore)
      echo "writing"; return ;;
    ai-sdk|ai-gateway|claude-api|mcp-builder|chat-sdk|nextjs|next-cache-components|next-best-practices|next-forge|react-best-practices|vercel-react-best-practices|turbopack|routing-middleware|runtime-cache|workflow|knowledge-update|bootstrap|env-vars|marketplace|vercel-cli|vercel-functions|vercel-sandbox|vercel-storage|vercel-agent|auth|vercel:*|claude-hud:*)
      echo "ai"; return ;;
    freeze|unfreeze|guard|careful|loop|simplify|less-permission-prompts|update-config|keybindings-help|caveman|caveman-*|caveman:*|compress|setup-browser-cookies|pair-agent|open-gstack-browser|commit|commit-push-pr|commit-commands:*|clean_gone|init|list-skills|plan-tune|gstack|using-superpowers|using-git-worktrees|finishing-a-development-branch|dispatching-parallel-agents|subagent-driven-development|test-driven-development|web-artifacts-builder)
      echo "workflow"; return ;;
    health|benchmark|benchmark-*|devex-review|plan-devex-review|realitycheck|plugin-audit|vercel-plugin-eval|cso)
      echo "analytics"; return ;;
    algorithmic-art|docx|pdf|pptx|xlsx|webapp-testing|xray)
      echo "other"; return ;;
  esac

  # Keyword fallback on description (lower precision).
  local d
  d=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
  case "$d" in
    *"deploy"*|*"ship"*|*"push to main"*|*"create a pr"*) echo "shipping"; return ;;
    *"qa "*|*"debug"*|*"investigate"*|*"find bugs"*|*"test this site"*) echo "debug"; return ;;
    *"design"*|*"aesthetic"*|*"visual art"*|*"poster"*) echo "design"; return ;;
    *"plan"*|*"architecture"*) echo "planning"; return ;;
    *"document"*|*"copywriting"*) echo "writing"; return ;;
    *"ai sdk"*|*"llm"*|*"anthropic"*|*"claude api"*|*"vercel"*|*"next.js"*) echo "ai"; return ;;
  esac

  echo "other"
}

# === bucket_label: bucket key -> emoji + display name ===
bucket_label() {
  case "$1" in
    shipping)  echo "🚀 Shipping & deploying" ;;
    debug)     echo "🔍 Debugging & QA" ;;
    design)    echo "🎨 Design & UX" ;;
    planning)  echo "📋 Planning & strategy" ;;
    writing)   echo "✍️ Writing & content" ;;
    ai)        echo "🤖 AI & integrations" ;;
    workflow)  echo "🛠️ Workflow tools" ;;
    analytics) echo "📊 Analytics & insight" ;;
    other)     echo "🧰 Other / misc" ;;
  esac
}

# === extract_trigger: pull "Use when..." chips from description ===
extract_trigger() {
  local desc="$1"
  local sentence
  sentence=$(printf '%s' "$desc" | grep -oiE 'use when [^.]*' 2>/dev/null | head -1)
  [ -z "$sentence" ] && return
  local triggers
  triggers=$(printf '%s' "$sentence" | grep -oE '"[^"]*"' 2>/dev/null | head -5 | tr -d '"' | paste -sd ',' - 2>/dev/null | sed 's/,/, /g')
  [ -n "$triggers" ] && printf '%s' "$triggers"
}

# === branch_suggestion: current branch verb -> suggested skills ===
branch_suggestion() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && return
  local verb="${branch%%/*}"
  case "$verb" in
    design)               printf '%s|%s' "$branch" "/design-review · /design-shotgun · /plan-design-review" ;;
    fix|bugfix|hotfix)    printf '%s|%s' "$branch" "/investigate · /qa · /review" ;;
    feat|feature)         printf '%s|%s' "$branch" "/plan-eng-review · /office-hours · /ship" ;;
    content)              printf '%s|%s' "$branch" "/doc-coauthoring · /review" ;;
    refactor)             printf '%s|%s' "$branch" "/review · /plan-eng-review" ;;
  esac
}

# === recently_used_raw: top 5 recent skills from telemetry ===
recently_used_raw() {
  local tel="$HOME/.gstack/analytics/skill-usage.jsonl"
  [ ! -f "$tel" ] && return
  [ ! -s "$tel" ] && return
  command -v jq >/dev/null 2>&1 || return

  tail -n 5000 "$tel" 2>/dev/null \
    | jq -r 'select(.skill != null and .ts != null) | "\(.skill)\t\(.ts)"' 2>/dev/null \
    | sort -k2 -r \
    | awk -F'\t' '!seen[$1]++ {print; if (++count==5) exit}'
}

# === relative_time: ISO 8601 -> "Nm/h/d ago" ===
relative_time() {
  local iso="$1"
  local then now diff
  then=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null) || return
  now=$(date -u +%s)
  diff=$((now - then))
  if   [ "$diff" -lt 3600 ];  then echo "$(( diff / 60  ))m ago"
  elif [ "$diff" -lt 86400 ]; then echo "$(( diff / 3600 ))h ago"
  else                              echo "$(( diff / 86400 ))d ago"
  fi
}

# === match: filter helper ===
match() {
  [ -z "$FILTER" ] && return 0
  printf '%s' "$1" | grep -iqF "$FILTER"
}

# === Main ===

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ALL="$TMP/all"
INSTALLED_NAMES="$TMP/installed_names"
: > "$ALL"; : > "$INSTALLED_NAMES"

# Personal scope
while IFS= read -r f; do
  parsed=$(parse_skill "$f")
  match "$parsed" || continue
  printf '%s\tpersonal\t-\n' "$parsed" >> "$ALL"
  printf '%s\n' "$parsed" | cut -f1 >> "$INSTALLED_NAMES"
done < <(find ~/.claude/skills -maxdepth 3 -name SKILL.md -type f 2>/dev/null | sort)

# Project scope
while IFS= read -r f; do
  parsed=$(parse_skill "$f")
  match "$parsed" || continue
  printf '%s\tproject\t-\n' "$parsed" >> "$ALL"
  printf '%s\n' "$parsed" | cut -f1 >> "$INSTALLED_NAMES"
done < <(find .claude/skills -maxdepth 3 -name SKILL.md -type f 2>/dev/null | sort)

# Plugin scope
while IFS= read -r f; do
  plugin=$(printf '%s' "$f" | sed -E 's|.*/plugins/([^/]+)/.*|\1|')
  parsed=$(parse_skill "$f")
  match "$parsed" || continue
  printf '%s\tplugin\t%s\n' "$parsed" "$plugin" >> "$ALL"
  printf '%s\n' "$parsed" | cut -f1 >> "$INSTALLED_NAMES"
done < <(find ~/.claude/plugins -maxdepth 6 -name SKILL.md -type f 2>/dev/null | sort)

# Plugin dedupe: same name + same first-100-chars-of-desc -> collapse, list registries.
DEDUPED="$TMP/deduped"
: > "$DEDUPED"

# Personal/project pass through
awk -F'\t' '$3 == "personal" || $3 == "project"' "$ALL" >> "$DEDUPED"

# Plugin dedupe by (name, substr(desc,1,100))
awk -F'\t' '
  $3 == "plugin" {
    name = $1; desc = $2; plugin = $4
    key = name "|" substr(desc, 1, 100)
    if (key in firstdesc) {
      plugins[key] = plugins[key] ", " plugin
    } else {
      firstname[key] = name
      firstdesc[key] = desc
      plugins[key] = plugin
    }
  }
  END {
    for (k in firstname) {
      printf "%s\t%s\tplugin\t%s\n", firstname[k], firstdesc[k], plugins[k]
    }
  }
' "$ALL" >> "$DEDUPED"

TOTAL_COUNT=$(wc -l < "$DEDUPED" | tr -d ' ')

# Classify
CLASSIFIED="$TMP/classified"
: > "$CLASSIFIED"
while IFS=$'\t' read -r name desc scope plugins; do
  bucket=$(classify_intent "$name" "$desc")
  printf '%s\t%s\t%s\t%s\t%s\n' "$bucket" "$name" "$desc" "$scope" "$plugins" >> "$CLASSIFIED"
done < "$DEDUPED"

# Branch suggestion
BS=$(branch_suggestion)

# Recently used (intersected with installed names to suppress stale entries)
RU=""
RU_RAW=$(recently_used_raw)
if [ -n "$RU_RAW" ] && [ -s "$INSTALLED_NAMES" ]; then
  RU=$(printf '%s\n' "$RU_RAW" | while IFS=$'\t' read -r skill ts; do
    if grep -qFx "$skill" "$INSTALLED_NAMES"; then
      rel=$(relative_time "$ts")
      [ -n "$rel" ] && printf '/%s (%s)\n' "$skill" "$rel" || printf '/%s\n' "$skill"
    fi
  done | paste -sd ' · ' - 2>/dev/null)
fi

# === Emit markdown ===

if [ "$TOTAL_COUNT" -eq 0 ]; then
  if [ -n "$FILTER" ]; then
    echo "# Skills"
    echo
    echo "No skills matched filter \"${FILTER}\"."
  else
    echo "# Skills"
    echo
    echo "No skills installed."
  fi
  exit 0
fi

echo "# Skills · ${TOTAL_COUNT} total"
echo

if [ -n "$BS" ]; then
  branch_part="${BS%%|*}"
  suggestion_part="${BS#*|}"
  echo "**On \`${branch_part}\`** you might want: ${suggestion_part}"
  echo
fi

if [ -n "$RU" ]; then
  echo "**Recently used:** ${RU}"
  echo
fi

if [ -n "$FILTER" ]; then
  echo "*Filtered by \"${FILTER}\" — ${TOTAL_COUNT} match(es)*"
  echo
fi

BUCKETS="shipping debug design planning writing ai workflow analytics other"
OTHER_COUNT=0

for bucket in $BUCKETS; do
  count=$(awk -F'\t' -v b="$bucket" '$1 == b' "$CLASSIFIED" | wc -l | tr -d ' ')
  [ "$count" -eq 0 ] && continue

  if [ "$bucket" = "other" ]; then
    OTHER_COUNT=$count
  fi

  printf '## %s · %s\n\n' "$(bucket_label "$bucket")" "$count"

  awk -F'\t' -v b="$bucket" '$1 == b' "$CLASSIFIED" \
    | sort -t$'\t' -k2,2 \
    | while IFS=$'\t' read -r _ name desc scope plugins; do
        # Truncate long descriptions (markdown handles wrap, but we cap for readability)
        if [ ${#desc} -gt 140 ]; then
          desc="${desc:0:139}…"
        fi

        trigger=$(extract_trigger "$desc")

        plugin_badge=""
        if [ "$scope" = "plugin" ] && [ -n "$plugins" ] && [ "$plugins" != "-" ]; then
          plugin_badge=" *(via: ${plugins})*"
        fi

        if [ -n "$trigger" ]; then
          printf -- '- **`/%s`** — %s%s · *Use when: %s*\n' "$name" "$desc" "$plugin_badge" "$trigger"
        else
          printf -- '- **`/%s`** — %s%s\n' "$name" "$desc" "$plugin_badge"
        fi
      done
  echo
done

if [ "$OTHER_COUNT" -gt 0 ]; then
  echo "---"
  printf '*%d skill(s) uncategorized — extend the classifier in `~/.claude/commands/list-skills.md` if you want them grouped.*\n' "$OTHER_COUNT"
fi
```

Filter argument: $1
