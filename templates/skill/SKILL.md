---
name: brain
description: Autonomous project delivery system. Activate when user invokes /brain, asks to scaffold/build/deliver a project, integrates GSD/Superpowers workflows, or wants brain-managed project lifecycle (design→build→deploy→learn). The brain orchestrates GSD phases + Superpowers practices into one autonomous pipeline.
---

# Brain Skill — Autonomous Project Delivery

The brain is the orchestration layer that converts a design (from `/superpowers:brainstorming` or `/gsd-new-project`) into a fully delivered project — scaffolded, built, tested, deployed, and continuously learning.

## When to use

- User says `/brain`, `/brain create`, `/brain deliver`, `/brain init`, etc.
- User wants to scaffold a new project ("create a service desk for acme")
- User wants to build phases autonomously ("run phase 1", "deliver this project")
- User just finished a brainstorm/spec and wants to start building
- User asks about lessons, insights, or cross-project patterns
- Any project lifecycle action: design → build → deploy

## Vault location

- Vault: `~/vaults/automation-brain/`
- GitHub: https://github.com/goldiejz/automation-brain
- All vault writes auto-commit + push

## The Autonomous Pipeline

```
DESIGN PHASE
  /superpowers:brainstorming  → captures vision in chat
  OR /gsd-new-project          → generates ROADMAP.md with phases
  ↓
SCAFFOLD PHASE
  /brain create <name> --type <type> --customer <customer>
  → Writes CLAUDE.md, .planning/, src/lib/rbac.ts, package.json
  → git init + GitHub repo + brain integration
  ↓
DELIVERY PHASE (per ROADMAP phase)
  /brain deliver
  → For each phase:
    1. /gsd-plan-phase (or AI dispatch)
    2. /gsd-execute-phase (or Codex direct)
    3. /superpowers:test-driven-development (write tests first)
    4. brain verify (npm test + tsc)
    5. brain self-heal (if failure)
    6. brain deploy (wrangler/npm)
    7. /superpowers:verification-before-completion
    8. brain commit + push (atomic per phase)
    9. STATE.md updated
  ↓
LEARN PHASE (continuous)
  Stop hook auto-fires:
    → brain-extract-learnings (regex/AI)
    → Phase 6 daemon detects patterns
    → Vault updated, lessons available to next project
```

## Sub-commands

### `/brain` (default) or `/brain status`

1. Run: `bash ~/vaults/automation-brain/scripts/brain status` via Bash tool
2. Show snapshot version, lesson count, decision count
3. If no `.parent-automation/`, suggest `/brain init`

### `/brain create`

**This is the autonomous scaffold command.**

Required: project name + type + customer

If user hasn't specified, ask:
- Project name?
- Type? (`service-desk` | `revops` | `ops-intelligence` | `custom`)
- Customer name?

Then run via Bash:
```bash
bash ~/vaults/automation-brain/scripts/brain create <name> \
  --type <type> --customer <customer>
```

This writes ALL files (CLAUDE.md, .planning/*, src/lib/rbac.ts, package.json, wrangler.toml, etc.), creates GitHub repo, and integrates brain.

After: tell user `cd <path>` and run `/brain deliver` to start autonomous build.

### `/brain deliver`

**This is the autonomous build command.**

Run via Bash:
```bash
bash ~/vaults/automation-brain/scripts/brain deliver
```

The script reads ROADMAP.md and runs each phase autonomously. If ROADMAP isn't detailed enough, suggest user run `/gsd-plan-phase 1` first to populate Phase 1.

For each phase, the brain:
1. **Plans** — dispatches Codex or invokes `/gsd-plan-phase`
2. **Executes** — dispatches code generation
3. **Verifies** — runs tests, type checks
4. **Self-heals** — auto-fixes failures via Codex/Gemini
5. **Deploys** — wrangler or npm run deploy
6. **Commits** — atomic per phase, pushed to GitHub

Variants:
- `/brain deliver --phase N` — single phase only
- `/brain deliver --resume` — continue from last completed
- `/brain deliver --from-spec FILE` — start from brainstorm output

### `/brain init`

For projects that aren't scaffolded yet (existing imported codebase):
```bash
bash ~/vaults/automation-brain/scripts/brain init
```

Sets up `.parent-automation/`, copies query-brain.ts + bootstrap-v2.ts, syncs snapshot.

### `/brain align`

For imported projects with non-canonical structure:
```bash
bash ~/vaults/automation-brain/scripts/brain align
```

Standardizes: renames LEARNINGS.md → tasks/lessons.md, scans all .md files (including symlinks), generates doc-inventory.md, migrates project lessons to vault.

### `/brain doctor`

Comprehensive health check:
```bash
bash ~/vaults/automation-brain/scripts/brain doctor
```

27 checks: vault, scripts, hooks, registration, AI tools, Phase 6, project integration. Returns exit code for CI use.

### `/brain bootstrap`

Manual decision logging (records that you started a project, doesn't write files):
```bash
bash ~/vaults/automation-brain/scripts/brain bootstrap
```

Use this if you want to record a decision without scaffolding. Most users want `/brain create` instead.

### `/brain insights`

Show cross-project patterns from Phase 6:
```bash
bash ~/vaults/automation-brain/scripts/brain insights
```

### `/brain lessons`

List all lessons in the brain:
```bash
bash ~/vaults/automation-brain/scripts/brain lessons
```

### `/brain phase-6`

Manually trigger Phase 6 daemon:
```bash
bash ~/vaults/automation-brain/scripts/brain phase-6
```

### `/brain sync`

Pull latest vault from GitHub:
```bash
bash ~/vaults/automation-brain/scripts/brain sync
```

## Integration with other skills

### After `/superpowers:brainstorming`
The brainstorm produces a spec in chat. Invoke:
```
/brain create <name> --type custom --customer <user>
# Then edit .planning/PROJECT.md with the spec
/brain deliver
```

### After `/gsd-new-project`
GSD generates ROADMAP.md with phases. Invoke:
```
/brain create <name> --type <detected-type> --customer <user>
# .planning/ already populated by GSD
/brain deliver
```

### Combined with `/gsd-autonomous`
GSD has its own autonomous mode. Brain deliver complements by:
- Running brain-sync before each phase (gets latest patterns)
- Running self-heal after each phase failure
- Auto-deploying after each successful phase
- Recording decisions for cross-project learning

User can choose:
- `/gsd-autonomous` for pure GSD workflow
- `/brain deliver` for brain-orchestrated (calls GSD as needed)

### Combined with Superpowers
Brain deliver always uses these Superpowers patterns:
- `/superpowers:test-driven-development` — tests first, always
- `/superpowers:verification-before-completion` — at verify step
- `/superpowers:requesting-code-review` — after each phase commits
- `/superpowers:systematic-debugging` — when self-heal escalates

## Important rules

1. **Always invoke via Bash tool** — never try to run `brain` as a slash command
2. **Verify .parent-automation/ exists** before deliver/bootstrap commands
3. **Confirm with user before destructive ops** — `brain create` overwrites, `brain align` moves files
4. **Preserve existing customizations** — brain init/align always backs up first
5. **After scaffolding** — actually edit the stub files with real content using `Write` and `Edit` tools
6. **For deliver failures** — read self-healing/proposed/ and apply fixes manually if auto-apply didn't work
7. **Auto-commits are normal** — vault commits to GitHub continuously without user prompt

## Resources

- Vault: `~/vaults/automation-brain/`
- Scripts: `~/vaults/automation-brain/scripts/brain*.sh`
- Hooks: `~/.claude/hooks/brain-*.sh`
- Templates: `~/vaults/automation-brain/templates/`
- Lessons: `~/vaults/automation-brain/lessons/`
- Phase 6 outputs: `~/vaults/automation-brain/observability/`
- Self-heal proposals: `~/vaults/automation-brain/self-healing/proposed/`

## Flow Summary

User says: "build me an acme service desk"

You:
1. Confirm: type=service-desk, customer=acme
2. Run: `! brain create acme-service-desk --type service-desk --customer acme`
3. Help user define real scope: Use `Edit` tool to update `.planning/PROJECT.md` and `.planning/ROADMAP.md`
4. Run: `! brain deliver` (kicks off autonomous build)
5. Monitor progress, intervene if self-heal escalates
6. Final: GitHub repo with working deployed app
