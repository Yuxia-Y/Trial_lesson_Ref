#!/usr/bin/env bash
# diagnose.sh — measure Claude Code startup tax and per-component token cost
# Usage: bash diagnose.sh [project_root]
#   project_root defaults to current directory

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

# Initialize counters (avoid set -u unbound errors in edge cases)
total_mem_chars=0
total_mem_tokens=0
n_mem_files=0

# Approximate token counts: 1 token ≈ 3 chars for mixed CJK + English (conservative)
count_tokens() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local chars
    chars=$(wc -c < "$f" | tr -d ' ')
    echo $(( chars / 3 ))
  else
    echo 0
  fi
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Claude Context Tuner — Diagnose"
echo "  Project: $PROJECT_ROOT"
echo "  Time:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Project root discovery
if [[ -d "$PROJECT_ROOT/.git" ]]; then
  GIT_ROOT=$(cd "$PROJECT_ROOT" && git rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_ROOT")
  echo "[root] git repo detected: $GIT_ROOT"
else
  echo "[root] NOT a git repo — using: $PROJECT_ROOT"
fi
echo ""

# 2. Project-level tax
PROJECT_CLAUDE="$PROJECT_ROOT/CLAUDE.md"
echo "─── Project-level tax ─────────────────────────────────────────"
printf "  %-30s  %6s tokens  %s\n" "CLAUDE.md" "$(count_tokens "$PROJECT_CLAUDE")" "$PROJECT_CLAUDE"

# Look for common context files
for ctx in "docs/CONTEXT.md" "CONTEXT.md" "docs/overview.md" "README.md"; do
  f="$PROJECT_ROOT/$ctx"
  if [[ -f "$f" ]]; then
    printf "  %-30s  %6s tokens  %s\n" "$ctx" "$(count_tokens "$f")" "$f"
  fi
done
echo ""

# 3. Memory tax (auto-discover project memory dir)
# Convention: ~/.claude/projects/<sanitized-path>/memory/
# Sanitization rule (confirmed by user):
#   drive letter separator:  /e/  -->  E--
#   all other path '/':      /  -->  -
#   all underscores:         _  -->  -
#   uppercase the drive letter
# Example: /e/workspace/my_aibo  -->  E--workspace-my-aibo
# Drive letter detection: the first path component (after stripping leading /)
SANT=$(echo "$PROJECT_ROOT" | sed -E 's|^/([a-zA-Z])/|\1--|; s|/|-|g; s|_|-|g' | awk 'BEGIN{FS=OFS=""}{$1=toupper($1)}1')
if [[ -d "$HOME/.claude/projects/$SANT/memory" ]]; then
  SANITIZED="$SANT"
else
  SANITIZED="$SANT"  # display fallback
fi
MEM_DIR="$HOME/.claude/projects/$SANITIZED/memory"

echo "─── Memory tax ────────────────────────────────────────────────"
if [[ -d "$MEM_DIR" ]]; then
  echo "  Memory dir: $MEM_DIR"
  n_files=0
  total_mem_chars=0
  total_mem_tokens=0
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "MEMORY.md" ]] && continue  # index, small
    chars=$(wc -c < "$f" | tr -d ' ')
    toks=$(( chars / 3 ))
    total_mem_chars=$(( total_mem_chars + chars ))
    total_mem_tokens=$(( total_mem_tokens + toks ))
    n_files=$(( n_files + 1 ))
  done < <(find "$MEM_DIR" -maxdepth 1 -name "*.md" -type f)
  printf "  %-30s  %6s tokens  %d files\n" "memory/*.md (ex index)" "$total_mem_tokens" "$n_files"

  # Top 5 largest memory files
  echo ""
  echo "  Top 5 largest memory files:"
  find "$MEM_DIR" -maxdepth 1 -name "*.md" -type f -not -name "MEMORY.md" \
    -exec ls -la {} \; 2>/dev/null | sort -k5 -rn | head -5 | \
    awk '{printf "    %6s tokens  %s\n", int($5/3), $NF}'
else
  echo "  No memory dir found at $MEM_DIR"
fi
echo ""

# 4. Global tax
echo "─── Global tax ────────────────────────────────────────────────"
printf "  %-30s  %6s tokens  %s\n" "~/.claude/CLAUDE.md" "$(count_tokens "$GLOBAL_CLAUDE")" "$GLOBAL_CLAUDE"
echo ""

# 5. Tool schema tax (estimate)
# Built-in tools: Bash, Read, Write, Edit, Glob, Grep, TaskCreate, TaskUpdate, TaskList,
# TaskGet, TaskOutput, TaskStop, Skill, AskUserQuestion, WebFetch, WebSearch, NotebookEdit,
# CronCreate, CronDelete, CronList, EnterPlanMode, EnterWorktree, ExitPlanMode, ExitWorktree
# Conservative estimate: each schema ~300-700 tokens
TOOL_SCHEMA_TOKENS=8000
echo "─── Tool schema tax (built-in) ────────────────────────────────"
printf "  %-30s  %6s tokens  (estimated, varies by disabledTools)\n" "built-in tools" "$TOOL_SCHEMA_TOKENS"
echo ""

# 6. Total
total=0
for f in "$GLOBAL_CLAUDE" "$PROJECT_CLAUDE" "$PROJECT_ROOT/docs/CONTEXT.md" "$PROJECT_ROOT/CONTEXT.md"; do
  total=$(( total + $(count_tokens "$f") ))
done
total=$(( total + total_mem_tokens + TOOL_SCHEMA_TOKENS ))

echo "═══════════════════════════════════════════════════════════════"
echo "  TOTAL STARTUP TAX:  $total tokens"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Window reference:"
echo "    M3 / DeepSeek-1M (full)    1,000,000 tokens  (~$(( (1000000-total)*100/1000000 ))% headroom)"
echo "    Typical 32K window model     32,000 tokens  (~$(( 100-total*100/32000 ))% consumed)"
echo "    Typical 64K window model     64,000 tokens  (~$(( 100-total*100/64000 ))% consumed)"
echo ""
echo "Next: run scan-bloat.sh to find oversized files and narrative memory."
