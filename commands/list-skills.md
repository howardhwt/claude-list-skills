---
description: List installed skills, grouped by intent, with branch-aware suggestions
allowed-tools: Bash
argument-hint: "[filter]"
---

You are listing every installed Claude Code skill as a discovery tool, not a directory listing.

## Output rules

1. Run the bash script below. It prints **native markdown** — real `##` headers, real `**bold**`, emoji icons, plain bullet lists.
2. **Do NOT wrap the output in a fenced code block.** Relay the bash stdout to the user as your response text directly so chat renders it as formatted markdown.
3. Do not add any commentary above or below — the script is self-contained.
4. If a filter argument was passed and zero skills matched, the script prints a "No skills matched" line; pass that through unchanged.

## Bash

```bash
FILTER="$1"
CACHE_DIR="$HOME/.cache/list-skills"
CACHE_TSV="$CACHE_DIR/cache.tsv"
CACHE_SUM="$CACHE_DIR/checksum.txt"
CACHE_TTL="${LIST_SKILLS_TTL:-60}"
SCRIPT_PATH="$HOME/.claude/commands/list-skills.md"
mkdir -p "$CACHE_DIR"

# ── v4.2 Data flow ───────────────────────────────────────────────────
#
# Cache schema: bucket\tname\tdesc\ttrigger\tscope\tplugin (6 cols)
#                pre-sorted by (bucket, name) at write time
#
# Cold path (~250ms):
#   find paths → ONE awk parses + classifies + plugin-dedups + sorts
#   → write cache → filter → render awk emits bucket sections
#
# Warm TTL fast-path (<100ms target):
#   cache fresh → skip find+parse → filter → render awk
#
# Warm checksum-validate path (~150ms):
#   cache stale by TTL → recompute checksum (incl script mtime) → if
#   unchanged, reuse cache → filter → render
# ─────────────────────────────────────────────────────────────────────

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PARSED_TSV="$TMP/parsed.tsv"
CACHE_HIT=0

# === TTL fast-path: cache fresh AND schema valid (6 fields) ===
if [ "$CACHE_TTL" -gt 0 ] && [ -f "$CACHE_TSV" ] && [ -s "$CACHE_TSV" ]; then
  cache_mtime=$(stat -f %m "$CACHE_TSV" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$(( now - cache_mtime ))
  if [ "$age" -ge 0 ] && [ "$age" -lt "$CACHE_TTL" ]; then
    first_nf=$(awk -F'\t' 'NR==1 {print NF; exit}' "$CACHE_TSV")
    if [ "$first_nf" = "6" ]; then
      cp "$CACHE_TSV" "$PARSED_TSV"
      CACHE_HIT=1
    fi
  fi
fi

if [ "$CACHE_HIT" != "1" ]; then
  # === Find phase: 3 finds in parallel, tag each path with scope/plugin ===
  PATHS_TSV="$TMP/paths.tsv"
  {
    find ~/.claude/skills -maxdepth 3 -name SKILL.md -type f 2>/dev/null \
      | awk '{print "personal\t" $0 "\t-"}' &
    find .claude/skills -maxdepth 3 -name SKILL.md -type f 2>/dev/null \
      | awk '{print "project\t" $0 "\t-"}' &
    find ~/.claude/plugins -maxdepth 6 -name SKILL.md -type f 2>/dev/null \
      | awk '{
          plugin=$0; sub(/.*\/plugins\//, "", plugin); sub(/\/.*/, "", plugin)
          print "plugin\t" $0 "\t" plugin
        }' &
    wait
  } | sort -t$'\t' -k2 > "$PATHS_TSV"

  # === Checksum: skill paths + their mtimes + the script's mtime ===
  # Script mtime included so editing the classifier auto-invalidates cache.
  checksum_files() {
    if [ ! -s "$PATHS_TSV" ]; then echo "empty"; return; fi
    {
      stat -f '%N:%m' "$SCRIPT_PATH" 2>/dev/null
      awk -F'\t' '{print $2}' "$PATHS_TSV" | xargs stat -f '%N:%m' 2>/dev/null
    } | sort | shasum -a 1 2>/dev/null | awk '{print $1}'
  }
  CURRENT_SUM=$(checksum_files)

  if [ -f "$CACHE_SUM" ] && [ -f "$CACHE_TSV" ] && [ -s "$CACHE_TSV" ]; then
    STORED_SUM=$(cat "$CACHE_SUM" 2>/dev/null)
    first_nf=$(awk -F'\t' 'NR==1 {print NF; exit}' "$CACHE_TSV")
    if [ "$STORED_SUM" = "$CURRENT_SUM" ] && [ -n "$CURRENT_SUM" ] && [ "$first_nf" = "6" ]; then
      CACHE_HIT=1
    fi
  fi

  if [ "$CACHE_HIT" = "1" ]; then
    cp "$CACHE_TSV" "$PARSED_TSV"
    touch "$CACHE_TSV"
  else
    # === Cold path: ONE awk parses + classifies + plugin-dedups ===
    awk -F'\t' -v paths_file="$PATHS_TSV" '
      BEGIN {
        # Classifier patterns (translated from bash case)
        shipping_pat   = "^(ship|land-and-deploy|canary|deploy|deployments-cicd|setup-deploy|next-upgrade|gstack-upgrade|release|document-release)$"
        debug_pat      = "^(investigate|qa|qa-only|browse|review|security-review|webapp-testing|systematic-debugging|verification|verification-before-completion|diagnose)$"
        design_pat     = "^(design-html|design-review|design-shotgun|design-consultation|plan-design-review|vigglify|frontend-design|brand-guidelines|theme-factory|canvas-design|shadcn|slack-gif-creator)$"
        design_prefix  = "^figma[-:]"
        planning_pat   = "^(office-hours|autoplan|drill|brainstorming|brainstorm|writing-plans|write-plan|executing-plans|execute-plan|writing-skills|skill-creator|receiving-code-review|requesting-code-review|grill-me|to-prd|to-issues|triage|tdd|write-a-skill)$"
        planning_prefix= "^(plan-|superpowers:)"
        writing_pat    = "^(doc-coauthoring|internal-comms|retro|learn|context-save|context-restore|improve-codebase-architecture)$"
        ai_pat         = "^(ai-sdk|ai-gateway|claude-api|mcp-builder|chat-sdk|nextjs|next-cache-components|next-best-practices|next-forge|react-best-practices|vercel-react-best-practices|turbopack|routing-middleware|runtime-cache|workflow|knowledge-update|bootstrap|env-vars|marketplace|vercel-cli|vercel-functions|vercel-sandbox|vercel-storage|vercel-agent|auth)$"
        ai_prefix      = "^(vercel:|claude-hud:)"
        workflow_pat   = "^(freeze|unfreeze|guard|careful|loop|simplify|less-permission-prompts|update-config|keybindings-help|caveman|compress|setup-browser-cookies|pair-agent|open-gstack-browser|commit|commit-push-pr|clean_gone|init|list-skills|plan-tune|gstack|using-superpowers|using-git-worktrees|finishing-a-development-branch|dispatching-parallel-agents|subagent-driven-development|test-driven-development|web-artifacts-builder)$"
        workflow_prefix= "^(caveman[-:]|commit-commands:)"
        analytics_pat  = "^(health|devex-review|plan-devex-review|realitycheck|plugin-audit|vercel-plugin-eval|cso)$"
        analytics_prefix = "^benchmark"
        other_pat      = "^(algorithmic-art|docx|pdf|pptx|xlsx|xray)$"
        # Description keyword fallback
        desc_shipping  = "(deploy|ship|push to main|create a pr)"
        desc_debug     = "(qa |debug|investigate|find bugs|test this site)"
        desc_design    = "(design|aesthetic|visual art|poster)"
        desc_planning  = "(plan|architecture)"
        desc_writing   = "(document|copywriting)"
        desc_ai        = "(ai sdk|llm|anthropic|claude api|vercel|next\\.js)"

        # Load scope/plugin lookup
        while ((getline line < paths_file) > 0) {
          split(line, p, "\t")
          scope_of[p[2]] = p[1]
          plugin_of[p[2]] = p[3]
        }
        close(paths_file)
      }

      function classify(name, desc,    d) {
        if (name ~ shipping_pat)                          return "shipping"
        if (name ~ debug_pat)                             return "debug"
        if (name ~ design_pat || name ~ design_prefix)    return "design"
        if (name ~ planning_pat || name ~ planning_prefix) return "planning"
        if (name ~ writing_pat)                           return "writing"
        if (name ~ ai_pat || name ~ ai_prefix)            return "ai"
        if (name ~ workflow_pat || name ~ workflow_prefix) return "workflow"
        if (name ~ analytics_pat || name ~ analytics_prefix) return "analytics"
        if (name ~ other_pat)                             return "other"
        d = tolower(desc)
        if (d ~ desc_shipping) return "shipping"
        if (d ~ desc_debug)    return "debug"
        if (d ~ desc_design)   return "design"
        if (d ~ desc_planning) return "planning"
        if (d ~ desc_writing)  return "writing"
        if (d ~ desc_ai)       return "ai"
        return "other"
      }

      {
        file = $2; scope = $1; plugin = $3
        fm = 0; in_block = 0; name = ""; desc = ""

        while ((getline line < file) > 0) {
          if (line ~ /^---[[:space:]]*$/) {
            if (fm == 0) { fm = 1; continue } else { break }
          }
          if (fm == 0) continue
          if (in_block) {
            if (line ~ /^[A-Za-z_][A-Za-z0-9_-]*:/) { in_block = 0 }
            else { sub(/^[[:space:]]+/, "", line); if (line != "") desc = (desc == "" ? line : desc " " line); continue }
          }
          if (line ~ /^name:/) { sub(/^name:[[:space:]]*/, "", line); gsub(/^"|"$|^'\''|'\''$/, "", line); name = line }
          else if (line ~ /^description:/) {
            sub(/^description:[[:space:]]*/, "", line)
            if (line == "|" || line == ">" || line == "|-" || line == ">-" || line == "|+" || line == ">+") { in_block = 1; desc = "" }
            else { gsub(/^"|"$|^'\''|'\''$/, "", line); desc = line }
          }
        }
        close(file)

        if (name == "") { n = split(file, parts, "/"); name = parts[n-1] }
        if (desc == "") desc = "(no description)"
        gsub(/[[:space:]]+/, " ", desc); sub(/^ /, "", desc); sub(/ $/, "", desc)

        # Trigger chips
        trigger = ""
        if (match(tolower(desc), /use when [^.]*/)) {
          sentence = substr(desc, RSTART, RLENGTH)
          n_trig = 0; rest = sentence
          while (match(rest, /"[^"]+"/) && n_trig < 5) {
            phrase = substr(rest, RSTART + 1, RLENGTH - 2)
            trigger = (trigger == "" ? phrase : trigger ", " phrase)
            rest = substr(rest, RSTART + RLENGTH)
            n_trig++
          }
        }
        if (trigger == "") trigger = "-"

        bucket = classify(name, desc)

        if (scope == "plugin") {
          # Buffer for dedupe
          key = name "|" substr(desc, 1, 100)
          if (key in seen) {
            plugins_for[key] = plugins_for[key] ", " plugin
          } else {
            seen[key] = 1
            b_buf[key] = bucket
            n_buf[key] = name
            d_buf[key] = desc
            t_buf[key] = trigger
            plugins_for[key] = plugin
          }
        } else {
          printf "%s\t%s\t%s\t%s\t%s\t-\n", bucket, name, desc, trigger, scope
        }
      }

      END {
        for (k in seen) {
          printf "%s\t%s\t%s\t%s\tplugin\t%s\n", b_buf[k], n_buf[k], d_buf[k], t_buf[k], plugins_for[k]
        }
      }
    ' "$PATHS_TSV" | sort -t$'\t' -k1,1 -k2,2 > "$PARSED_TSV"

    cp "$PARSED_TSV" "$CACHE_TSV" 2>/dev/null
    echo "$CURRENT_SUM" > "$CACHE_SUM" 2>/dev/null
  fi
fi  # end CACHE_HIT != 1 cold-path

# === Build INSTALLED_NAMES from cache (pre-filter, for telemetry intersect) ===
INSTALLED_NAMES="$TMP/installed_names"
awk -F'\t' '{print $2}' "$PARSED_TSV" > "$INSTALLED_NAMES"

# === Filter (one awk pass) ===
FILTERED_TSV="$TMP/filtered.tsv"
if [ -n "$FILTER" ]; then
  awk -F'\t' -v f="$FILTER" '
    BEGIN { fl = tolower(f) }
    { if (index(tolower($2 "\t" $3), fl)) print }
  ' "$PARSED_TSV" > "$FILTERED_TSV"
else
  cp "$PARSED_TSV" "$FILTERED_TSV"
fi

TOTAL_COUNT=$(wc -l < "$FILTERED_TSV" | tr -d ' ')

# === Branch suggestion (bash, fast — uses git) ===
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
BS=$(branch_suggestion)

# === Recently-used (telemetry mining) ===
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

# Header
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

# === Single-awk render: emit all bucket sections + footer ===
awk -F'\t' '
  BEGIN {
    label["shipping"]  = "🚀 Shipping & deploying"
    label["debug"]     = "🔍 Debugging & QA"
    label["design"]    = "🎨 Design & UX"
    label["planning"]  = "📋 Planning & strategy"
    label["writing"]   = "✍️ Writing & content"
    label["ai"]        = "🤖 AI & integrations"
    label["workflow"]  = "🛠️ Workflow tools"
    label["analytics"] = "📊 Analytics & insight"
    label["other"]     = "🧰 Other / misc"
    n_order = split("shipping debug design planning writing ai workflow analytics other", order, " ")
  }

  {
    bucket = $1
    count[bucket]++
    rows[bucket] = (rows[bucket] == "" ? "" : rows[bucket] "\n") $0
  }

  END {
    other_count = 0
    for (i = 1; i <= n_order; i++) {
      b = order[i]
      if (count[b] == 0) continue
      if (b == "other") other_count = count[b]

      printf "## %s · %d\n\n", label[b], count[b]

      n_rows = split(rows[b], lines, "\n")
      for (j = 1; j <= n_rows; j++) {
        split(lines[j], f, "\t")
        # f[1]=bucket f[2]=name f[3]=desc f[4]=trigger f[5]=scope f[6]=plugin
        name = f[2]; desc = f[3]; trigger = f[4]; scope = f[5]; plugin = f[6]

        if (length(desc) > 140) desc = substr(desc, 1, 139) "…"

        plugin_badge = ""
        if (scope == "plugin" && plugin != "" && plugin != "-") {
          plugin_badge = " *(via: " plugin ")*"
        }

        if (trigger != "" && trigger != "-") {
          printf "- **`/%s`** — %s%s · *Use when: %s*\n", name, desc, plugin_badge, trigger
        } else {
          printf "- **`/%s`** — %s%s\n", name, desc, plugin_badge
        }
      }
      print ""
    }

    if (other_count > 0) {
      print "---"
      printf "*%d skill(s) uncategorized — extend the classifier in `~/.claude/commands/list-skills.md` if you want them grouped.*\n", other_count
    }
  }
' "$FILTERED_TSV"
```

Filter argument: $1
