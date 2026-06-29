#!/usr/bin/env bash
# Ralph loop: run Claude Code headless, one task per iteration, until done.
# Usage:  ./ralph/run.sh
# Stop:   Ctrl-C, or it stops itself on RALPH-COMPLETE / RALPH-PAUSE / RALPH-BLOCKED.
set -uo pipefail
cd "$(dirname "$0")/.."

PROMPT="$(cat ralph/PROMPT.md)"
MAX_ITERS="${MAX_ITERS:-40}"   # safety cap so it can't loop forever

for ((i = 1; i <= MAX_ITERS; i++)); do
  echo "===== Ralph iteration $i ====="
  OUT="$(claude -p "$PROMPT" --model claude-sonnet-4-6 --permission-mode bypassPermissions 2>&1)"
  echo "$OUT"

  if grep -q "RALPH-COMPLETE" <<<"$OUT"; then
    echo "All tasks complete. Stopping."; exit 0
  fi
  if grep -qE "RALPH-PAUSE|RALPH-BLOCKED" <<<"$OUT"; then
    echo "Loop paused — human needed. Stopping."; exit 1
  fi
  sleep 2
done
echo "Hit MAX_ITERS=$MAX_ITERS. Stopping (re-run to continue)."
