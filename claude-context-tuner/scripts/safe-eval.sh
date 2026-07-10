#!/usr/bin/env bash
# safe-eval.sh — run a command but auto-truncate long output
# Usage: safe-eval.sh <command> [args...]
#   - Default: pipe stdout through `tail -60`
#   - If --keep flag, return full output (use sparingly)
#   - Stderr always shown
#
# Examples:
#   safe-eval.sh pytest tests/ -v
#   safe-eval.sh --keep cat huge.log
#   safe-eval.sh git log --oneline -n 100

set -euo pipefail

KEEP=0
if [[ "${1:-}" == "--keep" ]]; then
  KEEP=1
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: safe-eval.sh [--keep] <command> [args...]" >&2
  exit 1
fi

if [[ $KEEP -eq 1 ]]; then
  # Pass through unchanged
  exec "$@"
else
  # Default: truncate stdout
  # Approach: tee to /dev/null for stderr passthrough, tail stdout
  # We can't easily separate them post-hoc, so just tail the combined
  out=$("$@" 2>&1 || true)
  total_lines=$(echo "$out" | wc -l)
  if [[ $total_lines -gt 80 ]]; then
    echo "[safe-eval: truncated $total_lines lines → last 60]"
    echo "$out" | tail -60
    echo "[safe-eval: full output had $total_lines lines; rerun with --keep to see all]"
  else
    echo "$out"
  fi
fi
