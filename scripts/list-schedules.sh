#!/bin/bash
# copilot-scheduler: List all registered scheduled tasks
#
# Usage:
#   bash list-schedules.sh [--json]

set -euo pipefail

SCHEDULER_DIR="$HOME/.copilot-scheduler"
JOBS_DIR="${SCHEDULER_DIR}/jobs"
JSON_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    *)      shift ;;
  esac
done

if [ ! -d "$JOBS_DIR" ] || [ -z "$(ls -A "$JOBS_DIR" 2>/dev/null)" ]; then
  if [ "$JSON_MODE" = true ]; then
    echo "[]"
  else
    echo "No scheduled tasks found."
    echo "Register one with: bash scripts/register-local.sh --cron \"0 9 * * *\" --prompt \"...\" --name \"my-task\""
  fi
  exit 0
fi

if [ "$JSON_MODE" = true ]; then
  echo "["
  FIRST=true
  for META in "${JOBS_DIR}"/*/meta.json; do
    [ -f "$META" ] || continue
    if [ "$FIRST" = true ]; then
      FIRST=false
    else
      echo ","
    fi
    cat "$META"
  done
  echo "]"
  exit 0
fi

# --- Table output ---
printf "%-20s %-18s %-8s %-40s\n" "NAME" "CRON" "NOTIFY" "PROMPT"
printf "%-20s %-18s %-8s %-40s\n" "----" "----" "------" "------"

for META in "${JOBS_DIR}"/*/meta.json; do
  [ -f "$META" ] || continue

  NAME=$(grep -o '"name": *"[^"]*"' "$META" | head -1 | sed 's/"name": *"//;s/"$//')
  CRON=$(grep -o '"cron": *"[^"]*"' "$META" | head -1 | sed 's/"cron": *"//;s/"$//')
  NOTIFY=$(grep -o '"notify": *"[^"]*"' "$META" | head -1 | sed 's/"notify": *"//;s/"$//')
  PROMPT=$(grep -o '"prompt": *"[^"]*"' "$META" | head -1 | sed 's/"prompt": *"//;s/"$//')

  # Truncate prompt for display
  if [ ${#PROMPT} -gt 37 ]; then
    PROMPT="${PROMPT:0:37}..."
  fi

  printf "%-20s %-18s %-8s %-40s\n" "$NAME" "$CRON" "$NOTIFY" "$PROMPT"
done

echo ""
echo "Total: $(ls -d "${JOBS_DIR}"/*/ 2>/dev/null | wc -l) task(s)"
