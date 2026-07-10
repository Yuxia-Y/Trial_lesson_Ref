---
name: claude-context-tuner
description: Diagnose why Claude Code context fills up fast in a project and apply evidence-based slimming (memory cleanup, CLAUDE.md rules, doc restructuring, tool/script additions). Bridges into self-improving-agent (`/si:review`, `/si:promote`) to graduate the discovered hygiene rules into permanent project rules. Use when user says "上下文爆了 / 100% 上下文 / context 满了 / 上下文健康检查 / 帮我瘦一下 / 文档太杂 / 上下文减负".
---

# Claude Context Tuner

Tune Claude Code's per-session context budget for a project. Two modes:
- **Diagnose + slim** (one-shot): profile startup tax, identify bloat sources, apply fixes
- **Maintain** (optional, opt-in): prevent regression via rules and optional CRON pruning

Bridges into `self-improving-agent` (`/si:review`, `/si:promote`) so discovered hygiene
patterns become permanent project rules rather than one-time notes.

## Quick start

```bash
# In any session, when user says context is filling up:
bash ~/.claude/skills/claude-context-tuner/scripts/diagnose.sh
bash ~/.claude/skills/claude-context-tuner/scripts/scan-bloat.sh
```

The two scripts print a profile. Read the output, then follow the workflow below.

## Workflow

```
Phase 1: Diagnose (always run first)
  ├─ diagnose.sh        — startup tax (CLAUDE.md / CONTEXT / memory / tool schema)
  └─ scan-bloat.sh      — large files, narrative-style memory, repeated tool_result bloat

Phase 2: Present findings
  └─ Show user: top-5 bloat sources + estimated tokens
  └─ Use AskUserQuestion to confirm which tier (档 1/2/3) to apply

Phase 3: Apply fixes (one tier at a time)
  ├─ Tier 1 (5 min): memory cleanup + CLAUDE.md rules + Bash tail discipline
  ├─ Tier 2 (30-60 min): doc restructuring (CONTEXT, ops, PRD slices)
  └─ Tier 3 (half day): scripts/aliases/CRON/disabledTools

Phase 4: Bridge into self-improving-agent
  ├─ After Tier 1 (memory cleanup): spawn `/si:review` to surface any patterns
  │  discovered during the diagnosis that should be promoted.
  ├─ Promote the hygiene rules ("don't write event narratives",
  │  "Grep before Read on large files", "pipe long bash output through tail")
  │  to the project's CLAUDE.md via `/si:promote`.
  └─ Confirm via `/si:status` that the memory layer is healthier.

Phase 5: Verify
  └─ Re-run diagnose.sh, confirm startup tax reduced ≥ 30%

Phase 6: Offer maintain (opt-in)
  └─ Show: rules added to CLAUDE.md, optional CRON prune
  └─ Do NOT install CRON without explicit user consent
```

## Why bridge into `/si:`?

The `self-improving-agent` plugin curates auto-memory and graduates recurring
patterns into enforced rules. The patterns we discover while slimming context
("memory should be for rules, not event logs"; "long bash output should be
tailed"; "Read large files with Grep first") are *exactly* the kind of
recurring, durable patterns that `/si:promote` is built for.

By calling `/si:review` after diagnosis, we let the plugin's own memory-analyst
spot patterns we'd miss, and by calling `/si:promote` for each hygiene rule,
we make the slimming *stick* across future sessions — not just this one.

We never modify the self-improving-agent plugin files directly. All `/si:`
calls are routed through the Skill tool, exactly as the user would invoke them.

## Hard rules (the skill itself must follow)

1. **Never auto-edit user files** without AskUserQuestion confirmation. Show diff preview first.
2. **Never delete memory files blindly.** Narrative-style memory (event logs) is the target; rule-style memory (constraints, gotchas) is sacred. Prefer extracting the rule into a 1-line note and `rm` the file.
3. **Never claim "fixed" without re-running diagnose.sh** and showing before/after numbers.
4. **Project-agnostic**: every path discovery goes through `git rev-parse --show-toplevel` or `~/.claude/CLAUDE.md` lookup. No hardcoded project paths.
5. **Tier order matters**: 1 → 2 → 3. Don't jump to restructuring without doing cleanup first.
6. **Never edit the self-improving-agent plugin cache** (`~/.claude/plugins/cache/...`). All `/si:` invocations go through the Skill tool only.
7. **Other sessions are using `/si:` concurrently** — be careful when reading/mutating `MEMORY.md`; use `Read` with offset/limit and edit minimal lines.

## Scripts

- `scripts/diagnose.sh` — measures startup tax and per-component token cost
- `scripts/scan-bloat.sh` — finds oversized files, narrative memory, repeated large tool_results
- `scripts/safe-eval.sh` — wrapper that auto-pipes long-output commands through `tail -60`

See `REFERENCE.md` for full tier-by-tier fix catalog and `EXAMPLES.md` for worked examples.

## Maintain mode (opt-in)

Tell the user:

> "If you want to prevent regression, I can add a 'context hygiene' section to your project's CLAUDE.md (rules the agent follows automatically) and optionally register a monthly memory-prune CRON. Both are opt-in — I won't add them without your explicit consent."

Default: **do nothing** until user says yes.
