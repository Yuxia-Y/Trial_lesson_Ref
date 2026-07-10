# Reference: Tier-by-tier fix catalog

## §1. The three costs (what diagnose.sh measures)

| Cost | Source | Default size | Notes |
|------|--------|--------------|-------|
| **System tax** | Global `~/.claude/CLAUDE.md` | 1-2K tok | Injected every session |
| **Project tax** | `<project>/CLAUDE.md` | 0.5-1K tok | Injected every session |
| **Context file** | Often `docs/CONTEXT.md` | 2-8K tok | Project convention; varies |
| **Memory tax** | `~/.claude/projects/<slug>/memory/*.md` | 5-15K tok | Auto-injected from MEMORY.md index |
| **Tool schema tax** | Built-in tool defs (Bash, Read, Write, Edit, Task, Skill, Agent, AskUserQuestion, WebFetch, WebSearch, etc.) | 5-10K tok | Mostly fixed; can shrink via `disabledTools` |

**Typical starting point**: 18-25K tokens before any user message. With a 32K window model, that's already 60-80% gone.

## §2. The three bloat sources (what scan-bloat.sh finds)

### 2.1 Narrative memory (event log style)

**Pattern**: memory file dated, describes "what was done today", cites commit hash and issue number, restates info already in git log.

**Examples to delete**:
- `m3-v05-completion.md`, `m3-v09-completion.md`, `m3-v10-completion.md`
- Anything with `description:` containing "完成于" / "完成 2026-XX-XX"

**Examples to keep**:
- `flutter-test-real-async-hang.md` (gotcha, not narrative)
- `github-access-via-ssh-over-443.md` (non-obvious constraint)
- `auto-mode-bash-wildcard-permissions.md` (rule the agent needs to follow)

**Heuristic**: If deleting the file would lose info that `git log` and `gh issue view` can't recover, keep it. Otherwise delete.

### 2.2 Oversized docs read in full

**Pattern**: a single `.md` file > 5K characters being read repeatedly.

**Common offenders**:
- `docs/CONTEXT.md` (project overview, dumped at session start)
- `docs/operations.md` (catch-all ops doc, read on every debug)
- `docs/prd/000X-bigmilestone.md` (entire PRD, when only one slice is active)

**Fix**: split into focused files. See §3.2.

### 2.3 Long tool_result blobs

**Pattern**: `Bash` or `Read` returning > 3K characters in a single tool result.

**Common offenders**:
- `pytest -v` output (full diff, full traceback)
- `cat huge.log` (entire log file)
- `git log` with no limit
- `Read` on a > 2K line file without offset/limit

**Fix**: see §3.3.

## §3. Fix catalog

### 3.1 Tier 1 — Quick wins (5 min, no architecture change)

**Memory cleanup**:
1. Run `scan-bloat.sh` to get a list of narrative-style memory
2. Show user the list + estimated token savings
3. For each candidate: extract any non-obvious rule/decision into a 1-line note in a `m3-design-decisions.md` style file, then `rm` the original
4. Update `MEMORY.md` index

**CLAUDE.md rules** — add this section to project's CLAUDE.md:

```markdown
## Context hygiene

1. Don't Read files > 5K chars unless user explicitly asks for "全文"
2. pytest / grep / cat long output: pipe through `| tail -50`
3. Memory is for rules and gotchas only. Don't write event narratives
   ("today V05 completed"). Use git log + gh issue for that.
4. To understand a large file, use `Grep` first, then `Read` with offset/limit
```

**Bash discipline** — add to global `~/.claude/CLAUDE.md` (not project):

```markdown
## Bash output

- Long stdout/stderr (> 2K chars) must be truncated before returning
- For pytest / logs / git log: default to `| tail -50` or `| head -30`
- If user needs full output, they will say so explicitly
```

**Expected savings**: 25-40% of startup tax, 30-50% of mid-session growth.

### 3.2 Tier 2 — Doc restructuring (30-60 min, one-time)

**Split `docs/CONTEXT.md`** (if > 5K chars):

```
docs/context/
├── _index.md           300 chars  ← Read this at session start
├── architecture.md
├── modules.md
└── commands.md
```

`_index.md` is just a router:

```markdown
# Project entry

Read me (300 tokens), then open subfiles via `Read` as needed.

- Current phase: see [project memory]
- Architecture: docs/context/architecture.md
- Module list: docs/context/modules.md
- Common commands: docs/context/commands.md
- ADRs: docs/adr/
```

Replace the old `docs/CONTEXT.md` with a 200-char stub pointing to `_index.md`. Or delete it if nothing else references it.

**Split `docs/operations.md`** (if > 8K chars):

```
docs/ops/
├── deploy.md
├── debug.md
├── monitor.md
├── git-workflow.md
└── ci.md
```

Each file should be ≤ 5K chars. If a section is > 5K, split it again.

**Split monolithic PRDs** (e.g. `docs/prd/0003-m3-pc.md` covering 18 stories):

```
docs/prd/m3/
├── README.md           1K — index, progress, links
├── V01-abstraction.md  1K
├── V02-install.md      1K
└── V18-e2e-ci.md       1K
```

CLAUDE.md rule: "Read `docs/prd/m3/README.md` for overview, then `docs/prd/m3/V<current>.md` for the active slice."

Update project memory to point at the new README, not the monolithic file.

**Expected savings**: 50-70% of startup tax.

### 3.3 Tier 3 — Toolchain (half day, optional)

**Add safe-eval.sh wrapper**:

```bash
# In ~/.bashrc or project-local
alias se="bash ~/.claude/skills/claude-context-tuner/scripts/safe-eval.sh"
# Usage: se pytest tests/   ← auto-piped through tail -60
```

**disabledTools in `~/.claude/settings.json`** (only disable what you don't use):

```json
{
  "disabledTools": ["WebFetch", "WebSearch"]
}
```

Each disabled tool saves ~500-1000 tokens of schema. Be honest about which you actually need.

**CLAUDE.md maintain rules** — add to project CLAUDE.md:

```markdown
## Maintain (do these every time)

- New memory file? Apply the 30-second test: "If `git log` + `gh issue view`
  can recover this info in 2 commands, don't write it to memory."
- New doc > 5K? Split before adding references.
- New bash command returning > 3K? Wrap in `| tail -50`.
```

**Optional CRON** (only with explicit user consent):

```bash
# ~/.claude/skills/claude-context-tuner/scripts/memory-prune.sh
# Move narrative-style memory files > 60 days old + > 2K chars to archive/

find ~/.claude/projects/*/memory/ -name "*.md" \
  -mtime +60 -size +2k \
  -not -name "MEMORY.md" \
  -exec mv {} ~/.claude/projects/*/memory/archive/ \;
```

Register with `CronCreate` (durable: true, cron: `7 3 1 * *` — first of month 03:07).

## §4. Verification protocol

After applying any tier, re-run `diagnose.sh` and compare to baseline:

| Tier | Target startup tax reduction |
|------|------------------------------|
| 1    | ≥ 25%                        |
| 2    | ≥ 60%                        |
| 3    | ≥ 70%                        |

Mid-session, monitor `~/.claude/timing.jsonl` (if hooks are configured) for `prompt_chars` growth rate. If a single prompt adds > 5K chars, that's a sign a tool result is still too big.

## §5. Common pitfalls

- **Don't touch `MEMORY.md` index** without updating it — orphan links break the auto-injection
- **Don't split a doc that's actively being edited** by other agents/processes
- **Don't disable a tool just because it's unused in this project** — global disable affects all projects
- **CLAUDE.md > 100 lines itself becomes a tax** — keep the hygiene section ≤ 30 lines

## §6. Bridging into self-improving-agent (`/si:`)

After Tier 1 (memory cleanup) and before Tier 2 (doc restructuring), bridge into
the `self-improving-agent` plugin to graduate the discovered hygiene patterns
into permanent project rules. The plugin is read-only from this skill's
perspective — we invoke its commands through the Skill tool, never edit its files.

### 6.1 When to call which `/si:` command

| Situation | Call | Why |
|-----------|------|-----|
| After Tier 1 memory cleanup, before Tier 2 doc split | `/si:review` | Surface any patterns discovered during diagnosis that the plugin's memory-analyst sees as promotion candidates |
| For each hygiene rule we add to CLAUDE.md manually | `/si:promote "<rule>"` | Formalize the rule in the project's rule system; future sessions get it auto-injected as a "promoted rule" not a "MEMORY note" |
| After all cleanup, before Phase 5 Verify | `/si:status` | Confirm memory layer is healthier; if line counts went up we did something wrong |
| After running for the first time on a project | `/si:remember "<one-liner>"` | Persist "this project uses `claude-context-tuner`; tier 1 already applied on <date>" as a single MEMORY entry |

### 6.2 The 3 hygiene rules to always promote

These recur across most projects. After Tier 1, run:

```
/si:promote "Don't write event narratives to memory ('V05 completed today').
             Use git log + gh issue for that. Memory is for rules and gotchas only."

/si:promote "For files > 5K chars: use `Grep` first to locate, then `Read` with
             offset/limit. Don't `Read` the full file unless user explicitly asks."

/si:promote "Long bash output (pytest, cat *.log, git log): pipe through
             `| tail -50` before returning. Default truncation; user can override with `| cat`."
```

If the project already has a CLAUDE.md hygiene section, /si:promote will
de-duplicate (the plugin checks for existing rules before adding).

### 6.3 Concurrent-session safety

The self-improving-agent plugin's hooks (error-capture) write to
`~/.claude/projects/<slug>/memory/MEMORY.md` from *any* running session. When
this skill touches memory files, it must:

1. **Read MEMORY.md with offset/limit** to avoid clobbering concurrent writes
2. **Edit minimal lines** — never `Write` the whole file
3. **Don't delete topic files other sessions may be reading** — only delete
   files this skill itself identified via `scan-bloat.sh`
4. **Skip if lock file present** — if `MEMORY.md.lock` exists, wait or
   delegate the write to `/si:promote` which handles its own locking

### 6.4 What this skill does NOT do via /si:

- It does NOT call `/si:extract` (extracting this skill itself is a different
  operation handled by `/si:extract claude-context-tuner`)
- It does NOT modify the self-improving-agent plugin cache or source
- It does NOT register its own CRON job (that's the maintain-mode opt-in)
- It does NOT spawn `memory-analyst` or `skill-extractor` agents directly —
  it calls them through the `/si:` slash commands, which is the supported path
