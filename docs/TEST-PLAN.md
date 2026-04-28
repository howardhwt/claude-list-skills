# Test Plan

## Smoke-test cases

The harness at `scripts/test.sh` runs 19 cases. Each runs the bash logic from `commands/list-skills.md` against the real installed skills + various env conditions, then asserts expected output snippets via grep.

### Filter & no-match

1. **Filter narrows results** — `/list-skills vercel` produces output containing `Filtered by "vercel"`.
2. **Filter scopes correctly** — output for filter `vercel` contains the literal `vercel`.
3. **No-match banner** — `/list-skills xyz999nonexistent` shows `No skills matched filter`.

### Intent grouping

4-6. **Intent headers render** — output contains `## 🚀 Shipping & deploying`, `## 🎨 Design & UX`, `## 📋 Planning & strategy`.

### Intent placement (skill → expected bucket)

7. `/ship` lands in 🚀 Shipping & deploying
8. `/investigate` lands in 🔍 Debugging & QA
9. `/design-review` lands in 🎨 Design & UX
10. `/office-hours` lands in 📋 Planning & strategy
11. `/ai-sdk` lands in 🤖 AI & integrations

### Plugin dedup

12. **Caveman has via-list** — output line for `/caveman` contains `(via: ...)` suffix.
13. **Caveman collapsed** — `/caveman` appears at most twice in full output (was 5 times before dedup).

### Trigger chips

14. **`/ship` shows trigger chips** — filtered output for `ship` contains `Use when:.*ship`.

### Branch awareness

15. **Suggestion line on recognized verb** — when current branch starts with `design/`, `fix/`, `bugfix/`, `hotfix/`, `feat/`, `feature/`, `content/`, or `refactor/`, output contains `On \`<branch>\``.
   **Negative case on unknown verb** — branches like `main`, `master` produce no `you might want:` line.

### Telemetry edge cases

16. **Telemetry missing** — with `~/.gstack/analytics/skill-usage.jsonl` moved aside, output has no `Recently used:` line.
17. **Telemetry malformed** — appending corrupt jsonl lines doesn't crash the script; output still starts with `# Skills`.

### Header invariants

18. **Total count line** — first line matches `^# Skills · [0-9]+ total`.
19. **Emoji rendered** — output contains literal `## 🚀` (not the escape sequence).

## Manual verification (after harness passes)

- Run `/list-skills` in Claude Code on a `design/*` branch → first non-header line should suggest `/design-review` and `/design-shotgun`.
- Verify markdown renders (real H2 headers, real bold) — not literal `## Header` text.
- Verify the plugin section is visibly cleaner than v3 (no N× duplicates of the same skill).
- Run `/list-skills vercel` → confirm filter narrows correctly to vercel-related skills.
- Switch to a `fix/` branch → confirm suggestion bar adapts to `/investigate`, `/qa`, `/review`.

## Critical paths (must work or v4 is broken)

- Markdown rendering (without it, no headers/bold visible — entire approach falls apart)
- Branch awareness on `design/`, `fix/`, `feat/`, `content/`, `refactor/` verbs
- Graceful fallback when git repo missing or telemetry missing
- Filter argument continues to work (v3 behavior preservation)

## Not tested (out of scope)

- Performance under huge skill registries (>500 skills). Current ~100 is fine.
- Concurrent invocations. Slash commands are sequential.
- ANSI color rendering. Confirmed unsupported in chat, intentionally not used.
- Linux/Windows. Built and tested on macOS.
