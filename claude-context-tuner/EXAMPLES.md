# Examples

## Example 1: my-aibo project (M2/M3 transition)

**Baseline** (from `diagnose.sh`):

```
Startup tax: 22,400 tokens
  Global CLAUDE.md:        1,300 tok
  Project CLAUDE.md:         800 tok
  docs/CONTEXT.md:         2,700 tok
  Memory (15 files):       8,500 tok
  Tool schema:             9,100 tok
```

**Findings** (from `scan-bloat.sh`):

```
Top bloat:
  docs/operations.md        16,200 chars  (read 3x this week)
  docs/prd/0003-m3-pc.md   17,500 chars  (read 5x this week)
  docs/prd/0002-m2.md      18,200 chars  (read 2x — already done)
  memory/m3-v05-completion  2,400 chars  (narrative)
  memory/m3-v09-completion  1,600 chars  (narrative)
  memory/m3-v10-completion  1,400 chars  (narrative)
```

**Actions taken** (Tier 1 + selective Tier 2):

1. Merged 3 narrative memories into `m3-design-decisions.md` (500 chars)
2. Added 4-line "Context hygiene" section to project CLAUDE.md
3. Added 3-line "Bash output" section to global CLAUDE.md

**After** (re-running `diagnose.sh`):

```
Startup tax: 15,800 tokens (-29%)
  Global CLAUDE.md:        1,700 tok  (+400 for new bash rule)
  Project CLAUDE.md:       1,200 tok  (+400 for hygiene rules)
  docs/CONTEXT.md:         2,700 tok  (untouched, defer to Tier 2)
  Memory (13 files):       2,100 tok  (-6,400)
  Tool schema:             9,100 tok  (untouched, defer to Tier 3)
```

User feedback: "下个 session 100% 触发频率明显下降"。

## Example 2: zhuanli project (patent drafting)

**Baseline**:

```
Startup tax: 14,200 tokens
  Global CLAUDE.md:        1,300 tok
  Project CLAUDE.md:       1,000 tok  (has 6 style functions, 4 inventor list)
  Memory (3 files):        1,200 tok
  Tool schema:             9,100 tok
```

This project is already well-tuned (the 6 style functions are project-specific rules, not bloat). diagnose.sh returned "no major issues, optional Tier 3 disabledTools trim only".

**Action taken** (Tier 3 light):

```json
// ~/.claude/settings.json
"disabledTools": ["WebFetch", "WebSearch"]
```

**After**:

```
Startup tax: 12,400 tokens (-13%)
  ... unchanged ...
  Tool schema:             7,300 tok  (-1,800 from disabled tools)
```

User feedback: "zhuanli 一直很正常，这次只是顺手优化下"。

## Example 3: A new project with severe bloat

User says: "新项目第一次进 Claude Code，session 才聊了 10 轮就 100% 了，怎么回事？"

**Workflow**:

1. Run `diagnose.sh` from project root
2. Run `scan-bloat.sh` from project root
3. Output shows: 35K startup tax, dominated by a 25K `docs/CONTEXT.md` that includes the entire architecture diagram, all ADRs, all command references
4. Present findings to user; recommend Tier 2 split
5. User confirms; do the split
6. Re-run `diagnose.sh`; confirm reduction

Expected outcome: startup tax 35K → 8K. User can now have 50+ turn sessions without hitting 100%.

## Example 4: End-to-end with `/si:` bridge (my-aibo, M3 phase)

User says: "my-aibo 上下文爆了，帮我瘦一下"。

**Step 1 — Diagnose**:
```bash
bash ~/.claude/skills/claude-context-tuner/scripts/diagnose.sh
# → Startup tax: 22,347 tokens
# → 16 memory files, 9,258 tokens; top file: m3-pc-prd.md (1,004 tok)
```

**Step 2 — Scan**:
```bash
bash ~/.claude/skills/claude-context-tuner/scripts/scan-bloat.sh
# → 4 narrative memory: m2-stage-completion + m3-v05/v09/v10 (2,311 tok total)
# → Largest tool_result: 19.7 KB (V04 IPC server read)
# → Top oversized file: docs/prd/0002-m2.md (6,055 tok, but M2 is done)
```

**Step 3 — AskUserQuestion to confirm tier 1**: user picks "Tier 1 only for now".

**Step 4 — Apply Tier 1 fixes**:
- Extract 3 design rules from `m3-v05-completion.md` into a new
  `m3-design-decisions.md` (500 chars total)
- `rm` the 4 narrative memory files
- Update `MEMORY.md` index
- Add 4-line "Context hygiene" section to `my-aibo/CLAUDE.md`
- Add 2-line "Bash output" rule to `~/.claude/CLAUDE.md`

**Step 5 — Bridge into `/si:`** (the new integration):
```
/si:review
# → memory-analyst flags the 3 design rules as promotion candidates
# → confirms the 3 narrative memory files are correctly deleted

/si:promote "Don't write event narratives to memory; use git log + gh issue"
/si:promote "Files > 5K chars: Grep first, then Read with offset/limit"
/si:promote "Long bash output: pipe through | tail -50"

/si:status
# → MEMORY.md: 14 files (was 16), 6,947 tokens (was 9,258) — 25% reduction
```

**Step 6 — Verify**:
```bash
bash ~/.claude/skills/claude-context-tuner/scripts/diagnose.sh
# → Startup tax: 16,100 tokens (-28%)
```

**Result**: User's next session starts with 28% less context. The 3 hygiene
rules are now promoted — future sessions will follow them automatically without
this skill needing to re-teach them. Other sessions using `/si:` are
unaffected (we only invoked public commands, never touched plugin files).
