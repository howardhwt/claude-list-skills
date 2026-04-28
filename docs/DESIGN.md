# Design: /list-skills v4 — Discovery surface, not directory listing

## Problem statement

The default `/list-skills` for Claude Code is a flat directory listing wrapped in an ASCII code block. With 100+ skills installed across personal, project, and plugin scopes, it functions as `ls` for skills — useful only if you already know what you're looking for. It doesn't help answer "what should I run right now?" or "is there a skill that does X?".

Three concrete failures observed in earlier iterations (v1-v3):

1. **Code-block monospace constraint forces description truncation** at ~42 chars, so the most signal-dense field gets cut off mid-sentence.
2. **Plugin section shows visible noise** — the same skill ships in multiple registries; truncation hides the only thing that distinguishes them, so you see e.g. `caveman` listed 5 times in identical-looking rows.
3. **Box-drawing characters (║│▸) had a font-substitution bug** in chat (rendered as bullets, collapsed the frame). v3 worked around with pure ASCII, but the underlying issue is fighting the rendering surface.

## What makes v4 cool

The current version reads like a wall. v4 reads like a smart panel that already knows:

- What you're working on (branch verb → recommended skills)
- What you've used recently (top 5 from telemetry, with timestamps)
- What each skill is *for* (trigger phrases extracted from "Use when..." patterns)
- What category each skill belongs to (intent grouping, not filesystem grouping)

The whoa moment: open `/list-skills` on a `fix/` branch and the first thing you see is "On `fix/auth-token-bug` you might want `/investigate`, `/qa`, `/review`" — without ever having configured anything.

## Premises

1. **Native markdown rendering beats ASCII code blocks here.** Drop the fenced code block. Use real `##` headers, `**bold**` skill names, emoji icons, and lists. Trade column alignment for visual hierarchy that survives any font.
2. **Group by intent, not by file scope.** "Shipping & deploying", "Debugging & QA", "Design & UX" maps to how you actually search. Personal-vs-Plugins is a filesystem detail you don't care about at lookup time. Show it as metadata, not a primary axis.
3. **Surface usage signal — don't list 100+ skills equally.** Mine `~/.gstack/analytics/skill-usage.jsonl` for top-N recent. Combine with branch-aware suggestions. Long tail still listed, but de-emphasized.

## Approaches considered

### Approach A: Markdown rewrite + keyword grouping
Minimum viable. Rewrite the bash to emit native markdown, keyword-match each description against intent buckets, show top 5 most-recent. No trigger chips, no branch awareness. Completeness 7/10.

### Approach B: Categorized + branch-aware recommendations + trigger chips ⭐ Recommended
Approach A plus three things that turn it from a list into a discovery tool:

- **Trigger chips.** Regex `Use when (asked to|you)\s+[^.]*` extracts the trigger phrase from each description, dedupes, and renders it next to the skill name as a chip.
- **Branch-aware recommendations.** Read the current branch, extract the verb prefix (`design/`, `fix/`, `feat/`, `content/`), suggest 3-5 contextually relevant skills at the top.
- **Recently-used row.** Top 5 from analytics with last-run timestamp inline.

Completeness 9/10.

### Approach C: Generated browser registry
Lateral. Bash builds a full HTML page with search box, click-to-expand cards, real CSS color, electric green accents. `/list-skills` shows a 5-line summary in chat plus "→ Open full registry". Completeness 10/10 if used, 5/10 if not (out-of-flow — breaks chat-native usage pattern).

## Recommended approach

**Approach B.** The "what skill should I run?" moment happens in the chat, so the answer should land in the chat. C's beautiful registry is a doc, not a tool. A is half of B for nearly the same work — the trigger chips and branch awareness are what turn this from a list into a discovery tool, and they're not expensive to add.

## Key decisions

- **Plugin dedup key:** `name + sha1(description[0:100])`. Same name AND same description = same skill. Different name OR different desc = different entry. Catches both legit duplicates and accidentally-shared names.
- **Telemetry handling:** pipe through `tail -n 5000 | jq -e .skill` before sorting. Handles unbounded growth + drops malformed jsonl lines.
- **Stale telemetry suppression:** Before emitting the recently-used line, intersect telemetry skill names with currently-installed names. Drop entries that no longer have a matching SKILL.md.
- **Trigger fallback:** Skip the chip line cleanly when no "Use when..." pattern matches. Don't synthesize fallback chips — quality > coverage.
- **Uncategorized footer:** Count skills classified as "Other". If > 0, append a footer line reminding to extend the classifier. Maintenance feedback loop.

## Eureka moment

Plan rolls a custom intent classifier instead of adding a `category:` field to each SKILL.md frontmatter. Adding `category:` would give us reliable classification with zero keyword-matching guesswork — but we don't own most of those files (plugins, gstack family, vercel-plugin, etc.). Custom classifier is the correct call.

## Architecture

```
                                +-------------------------+
                                | /list-skills [filter]   |
                                +-----------+-------------+
                                            |
                            +---------------+---------------+
                            |                               |
                            v                               v
                  +-------------------+         +----------------------+
                  | branch_suggestion |         | recently_used        |
                  | (git + verb map)  |         | (telemetry jsonl)    |
                  +---------+---------+         +-----------+----------+
                            |                               |
                            v                               v
                  +---------+-------------------------------+----------+
                  |                  Header block                       |
                  +---------------------------+--------------------------+
                                              |
                                              v
                          +-------------------+--------------------+
                          | for each SKILL.md (3 scopes):          |
                          |   parse_skill -> name, desc            |
                          |   match($FILTER)                       |
                          |   classify_intent -> bucket            |
                          |   extract_trigger -> chip              |
                          |   plugin_dedup (if plugin scope)       |
                          +-------------------+--------------------+
                                              |
                                              v
                              +---------------+--------------+
                              |  Group by intent bucket      |
                              |  Sort within bucket          |
                              +---------------+--------------+
                                              |
                                              v
                              +---------------+--------------+
                              |  Emit markdown               |
                              |  (no fenced code block)      |
                              +------------------------------+
```

## Failure modes

| Codepath | Failure mode | Defense |
|---|---|---|
| `branch_suggestion()` | Git repo missing | silent skip |
| `branch_suggestion()` | Verb not in mapping (`hotfix/`, `chore/`) | silent skip |
| `recently_used()` | Telemetry file missing | silent skip |
| `recently_used()` | Malformed jsonl line | `jq -e` filter drops it |
| `recently_used()` | Skill in telemetry but uninstalled | intersect with installed names, drop stale entries |
| `extract_trigger()` | Description has no "Use when..." pattern | empty chip line (graceful absence) |
| `classify_intent()` | New skill not in vocabulary | "Other" bucket + footer note |
| `plugin_dedup()` | Same name, different desc-hash | keep separate |
| Markdown render | Chat doesn't render markdown | confirmed renders for assistant text relay |

## Not in scope

- **Approach C — browser HTML registry.** Considered, deferred. The "what skill?" moment is in-chat. Revisit only if Approach B in chat proves insufficient for discovery.
- **`category:` frontmatter on SKILL.md files.** Considered as cleaner classification source. Rejected because we don't own most files.
- **ANSI color.** Chat doesn't render escape codes. Markdown bold/headers carry visual hierarchy instead.
- **Interactive fuzzy search / arrow-key nav.** Not possible in chat surface.
- **Per-skill usage analytics dashboard.** Beyond scope. Recently-used line is enough signal.
- **Caching parsed SKILL.md output.** Premature optimization at ~50ms wall-time.
- **Full bash test framework (bats-core).** Replaced by lightweight smoke-test script.
- **Listing system-injected skills** (`/claude-api`, `/init`, `/review`, etc.). They're not on disk; would require a separate harness query.
