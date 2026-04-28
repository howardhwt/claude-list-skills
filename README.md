# claude-list-skills

A `/list-skills` slash command for [Claude Code](https://claude.com/claude-code) that turns the skills registry into a **discovery tool** instead of a flat directory listing.

## What you get

- **Grouped by intent** — 🚀 Shipping, 🔍 Debugging, 🎨 Design, 📋 Planning, ✍️ Writing, 🤖 AI, 🛠️ Workflow, 📊 Analytics, 🧰 Other. Search by what you're trying to do, not by where the file lives.
- **Branch-aware suggestions** — on a `design/` branch, the top of the output suggests `/design-review`, `/design-shotgun`, `/plan-design-review`. On `fix/`, it surfaces `/investigate`, `/qa`, `/review`. Knows about `design`, `fix`/`bugfix`/`hotfix`, `feat`/`feature`, `content`, `refactor`.
- **Recently-used row** — top 5 skills you ran lately with relative timestamps (`/ship (2h ago)`), pulled from gstack telemetry if present. Silently skipped if you don't have gstack.
- **Trigger chips** — pulls the `Use when "X", "Y"...` snippets from each skill's description and shows them inline. So you see what each skill is *for* without clicking through.
- **Plugin dedup** — same skill ships in multiple plugin registries? Collapses into one entry with a `(via: cache, marketplaces)` suffix instead of N visually identical rows.
- **Filter argument** — `/list-skills vercel` narrows to vercel-related skills with a filter banner.
- **Native markdown rendering** — real headers, real bold, emoji icons. No ASCII art, no font-substitution bugs.

## Install

### As a Claude Code plugin (recommended)

```bash
git clone https://github.com/howardhwt/claude-list-skills.git ~/.claude/plugins/list-skills
```

Or, if you prefer to keep the source elsewhere:

```bash
git clone https://github.com/howardhwt/claude-list-skills.git
ln -s "$(pwd)/claude-list-skills" ~/.claude/plugins/list-skills
```

Restart Claude Code (or run `/plugin reload` if your version supports it). Then run `/list-skills`.

### Manual install (no plugin)

If you don't want it as a plugin, just drop the slash command into your personal commands directory:

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/howardhwt/claude-list-skills/main/commands/list-skills.md \
  -o ~/.claude/commands/list-skills.md
```

## Use

```
/list-skills              # full discovery view
/list-skills vercel       # filter to skills matching "vercel"
/list-skills design       # filter to skills matching "design"
```

## Verify

Smoke-test harness — runs 19 cases covering classification, plugin dedup, branch awareness, telemetry handling, filter behavior, and edge cases.

```bash
# Against the repo
bash scripts/test.sh

# Against an installed copy
bash scripts/test.sh ~/.claude/commands/list-skills.md
```

Expected output ends with `PASS: 19   FAIL: 0`.

## Customize

The classifier vocabulary lives inside `commands/list-skills.md` in the `classify_intent()` bash function. Two layers:

1. **Explicit name mappings** (highest precision). Edit the `case "$name" in ...` block to assign known skills to specific buckets.
2. **Description keyword fallback** (for unknown skills). Edit the `case "$d" in ...` block to add keyword patterns.

If a skill ends up in 🧰 Other, a footer appears reminding you to extend the classifier:

> *N skill(s) uncategorized — extend the classifier in `~/.claude/commands/list-skills.md` if you want them grouped.*

That's the maintenance feedback loop. New skills land in Other until you update the vocabulary.

To add a new branch-verb mapping, edit `branch_suggestion()`:

```bash
case "$verb" in
  design)               printf '%s|%s' "$branch" "/design-review · /design-shotgun · /plan-design-review" ;;
  fix|bugfix|hotfix)    printf '%s|%s' "$branch" "/investigate · /qa · /review" ;;
  # add your own:
  chore)                printf '%s|%s' "$branch" "/your-skill · /another" ;;
esac
```

## Why

The default skill registry experience for Claude Code is a flat ASCII listing of every installed skill. With 100+ skills (which adds up fast once you install gstack, vercel-plugin, figma-plugin, superpowers, etc.), that listing functions as `ls` for skills — useful only if you already know what you're looking for.

This version answers a different question: **"what should I run right now?"** — by combining intent grouping, branch context, and recent usage into a single view.

## Limitations

- Only lists skills with a `SKILL.md` on disk under `~/.claude/skills/`, `.claude/skills/` (project-local), or `~/.claude/plugins/`. **System-injected skills** that ship inside the Claude Code app bundle (`/init`, `/review`, `/security-review`, `/claude-api`, `/update-config`, etc.) are not on disk and therefore not listed. They're discoverable only via the active session's tool listing.
- Recently-used row requires [gstack](https://gstack.dev) telemetry at `~/.gstack/analytics/skill-usage.jsonl`. If you don't have gstack, the line is silently skipped.
- Built and tested on macOS. Linux should work with minor `date` syntax tweaks (the `relative_time()` helper uses BSD-flavor `date -j -f`). Untested on Windows.

## Development

- [docs/DESIGN.md](docs/DESIGN.md) — design doc with problem statement, alternatives considered, recommended approach.
- [docs/TEST-PLAN.md](docs/TEST-PLAN.md) — smoke-test cases and manual verification steps.

## License

MIT — see [LICENSE](LICENSE).
