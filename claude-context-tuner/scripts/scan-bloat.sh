#!/usr/bin/env bash
# scan-bloat.sh — find oversized docs, narrative memory, and repeated large tool_results
# Usage: bash scan-bloat.sh [project_root]

set -euo pipefail

PROJECT_ROOT="${1:-$(pwd)}"
# Path sanitization rule (confirmed by user):
#   drive letter separator:  /e/  -->  E--
#   all other path '/':      /  -->  -
#   all underscores:         _  -->  -
#   uppercase the drive letter
# Example: /e/workspace/my_aibo  -->  E--workspace-my-aibo
SANT=$(echo "$PROJECT_ROOT" | sed -E 's|^/([a-zA-Z])/|\1--|; s|/|-|g; s|_|-|g' | awk 'BEGIN{FS=OFS=""}{$1=toupper($1)}1')
if [[ -d "$HOME/.claude/projects/$SANT" ]]; then
  SANITIZED="$SANT"
else
  SANITIZED="$SANT"  # display fallback
fi
MEM_DIR="$HOME/.claude/projects/$SANITIZED/memory"
SESSION_DIR="$HOME/.claude/projects/$SANITIZED"

echo "═══════════════════════════════════════════════════════════════"
echo "  Bloat Scan"
echo "  Project: $PROJECT_ROOT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Oversized .md files in the project
echo "─── 1. Oversized .md files (≥ 3K chars, top 10) ──────────────"
if command -v find &>/dev/null; then
  find "$PROJECT_ROOT" -type f -name "*.md" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/build/*" \
    -not -path "*/.venv/*" \
    -not -path "*/__pycache__/*" \
    -size +3k 2>/dev/null | \
    xargs -I{} ls -la "{}" 2>/dev/null | \
    sort -k5 -rn | head -10 | \
    awk '{
      toks = int($5/3)
      printf "    %6d tok  %6.1f KB  %s\n", toks, $5/1024, $NF
    }'
else
  echo "  (find not available)"
fi
echo ""

# 2. Narrative-style memory candidates
echo "─── 2. Narrative-style memory (event-log pattern) ───────────"
if [[ -d "$MEM_DIR" ]]; then
  n_narrative=0
  total_narrative_chars=0
  # Heuristics: frontmatter description contains "完成" / "completed" / "于 2026"
  # OR body contains commit hash + issue number combo
  for f in "$MEM_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "MEMORY.md" ]] && continue
    fname=$(basename "$f")
    # Check frontmatter description
    if grep -qE "description:.*(完成|completed|于 20[0-9][0-9])" "$f" 2>/dev/null; then
      chars=$(wc -c < "$f" | tr -d ' ')
      total_narrative_chars=$(( total_narrative_chars + chars ))
      n_narrative=$(( n_narrative + 1 ))
      printf "    %-40s  %4d chars  (frontmatter says 'completed')\n" "$fname" "$chars"
      continue
    fi
    # Check body for commit + issue combo
    if grep -qE "commit.*[0-9a-f]{7,}.*issue.*#[0-9]+" "$f" 2>/dev/null; then
      chars=$(wc -c < "$f" | tr -d ' ')
      total_narrative_chars=$(( total_narrative_chars + chars ))
      n_narrative=$(( n_narrative + 1 ))
      printf "    %-40s  %4d chars  (body has commit+issue)\n" "$fname" "$chars"
    fi
  done
  if [[ $n_narrative -eq 0 ]]; then
    echo "    (no narrative candidates found)"
  else
    echo ""
    echo "    Total narrative: $n_narrative files, $total_narrative_chars chars (~ $(( total_narrative_chars / 3 )) tokens)"
  fi
else
  echo "  (no memory dir)"
fi
echo ""

# 3. Large tool_results in recent session jsonl files
echo "─── 3. Largest tool_results in recent sessions (top 10) ──────"
if [[ -d "$SESSION_DIR" ]]; then
  # Pick the 3 most recent session files
  sessions=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -3)
  if [[ -z "$sessions" ]]; then
    echo "  (no session files)"
  else
    found_any=0
    for sess in $sessions; do
      sess_short=$(basename "$sess" .jsonl | cut -c1-8)
      # Use python for JSON parsing (reliable cross-platform)
      python - "$sess" "$sess_short" <<'PYEOF' 2>/dev/null && found_any=1
import json, sys
fn, short = sys.argv[1], sys.argv[2]
sizes = []
with open(fn, 'r', encoding='utf-8') as f:
    for i, line in enumerate(f):
        try: d = json.loads(line)
        except: continue
        if d.get('type') != 'user': continue
        content = d.get('message', {}).get('content', [])
        if not isinstance(content, list): continue
        for c in content:
            if isinstance(c, dict) and c.get('type') == 'tool_result':
                rc = c.get('content', '')
                if isinstance(rc, str):
                    sizes.append((len(rc), i, rc[:60].replace('\n', '⏎')))
                elif isinstance(rc, list):
                    for x in rc:
                        if isinstance(x, dict) and x.get('type') == 'text':
                            sizes.append((len(x.get('text','')), i, x.get('text','')[:60].replace('\n', '⏎')))
sizes.sort(reverse=True)
for sz, idx, excerpt in sizes[:5]:
    excerpt_one_line = excerpt.replace('\r', ' ').replace('\n', '⏎')
    print(f"    sess={short}  {sz/1024:5.1f} KB  msg#{idx}  {excerpt_one_line}")
PYEOF
    done
  fi
else
  echo "  (no session dir)"
fi
echo ""

# 4. Repeated Read patterns (signs of full-file reads on big files)
echo "─── 4. Read call frequency on large files (top 5) ───────────"
if [[ -d "$SESSION_DIR" ]]; then
  python - "$SESSION_DIR" <<'PYEOF' 2>/dev/null
import json, os, sys
from collections import Counter
sess_dir = sys.argv[1]
read_paths = Counter()
for fn in os.listdir(sess_dir):
    if not fn.endswith('.jsonl'): continue
    full = os.path.join(sess_dir, fn)
    with open(full, 'r', encoding='utf-8') as f:
        for line in f:
            try: d = json.loads(line)
            except: continue
            if d.get('type') != 'assistant': continue
            content = d.get('message', {}).get('content', [])
            if not isinstance(content, list): continue
            for c in content:
                if isinstance(c, dict) and c.get('type') == 'tool_use' and c.get('name') == 'Read':
                    fp = c.get('input', {}).get('file_path', '')
                    if fp and os.path.getsize(fp) > 3000:
                        read_paths[fp] += 1
if not read_paths:
    print("    (no large file reads detected)")
else:
    for path, n in read_paths.most_common(5):
        size = os.path.getsize(path) if os.path.exists(path) else 0
        print(f"    {n:3d}x  {size/1024:5.1f} KB  {path}")
PYEOF
fi
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "  Recommendations (heuristic):"
echo "    • Files ≥ 8K chars: candidates for splitting"
echo "    • Files ≥ 15K chars: should definitely be split"
echo "    • Narrative memory: extract any non-obvious rule, then delete"
echo "    • tool_results ≥ 5K: bash commands need pipe-tail discipline"
echo "    • Repeated Read on large files: agent needs Grep-first discipline"
echo "═══════════════════════════════════════════════════════════════"
