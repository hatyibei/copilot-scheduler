#!/bin/bash
# copilot-scheduler: Unregister a scheduled Copilot task
#
# Usage:
#   bash unregister-local.sh --name "task-name"
#   bash unregister-local.sh --all

set -euo pipefail

SCHEDULER_DIR="$HOME/.copilot-scheduler"
JOBS_DIR="${SCHEDULER_DIR}/jobs"
LOCK_DIR="${SCHEDULER_DIR}/locks"

NAME=""
ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --all)  ALL=true;  shift ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      echo "Usage: unregister-local.sh --name \"task-name\" | --all" >&2
      exit 1
      ;;
  esac
done

if [ "$ALL" = false ] && [ -z "$NAME" ]; then
  echo "Error: --name or --all is required." >&2
  exit 1
fi

remove_job() {
  local job_name="$1"
  local job_dir="${JOBS_DIR}/${job_name}"

  if [ ! -d "$job_dir" ]; then
    echo "Warning: Job '${job_name}' not found in ${JOBS_DIR}." >&2
    return 1
  fi

  # Remove from crontab
  CURRENT_CRONTAB="$(crontab -l 2>/dev/null || true)"
  if [ -n "$CURRENT_CRONTAB" ]; then
    # Remove the comment line and the cron entry line that follows it
    NEW_CRONTAB=$(echo "$CURRENT_CRONTAB" | grep -v "# copilot-scheduler:${job_name}$" | grep -v "${JOBS_DIR}/${job_name}/run.sh")
    echo "$NEW_CRONTAB" | crontab -
  fi

  # Remove job directory
  rm -rf "$job_dir"

  # Remove lock file
  rm -f "${LOCK_DIR}/${job_name}.lock"

  echo "Removed: ${job_name}"
}

if [ "$ALL" = true ]; then
  if [ ! -d "$JOBS_DIR" ] || [ -z "$(ls -A "$JOBS_DIR" 2>/dev/null)" ]; then
    echo "No scheduled tasks to remove."
    exit 0
  fi

  COUNT=0
  for JOB_DIR in "${JOBS_DIR}"/*/; do
    [ -d "$JOB_DIR" ] || continue
    JOB_NAME=$(basename "$JOB_DIR")
    remove_job "$JOB_NAME" && COUNT=$((COUNT + 1))
  done
  echo ""
  echo "Removed ${COUNT} task(s)."
else
  remove_job "$NAME"
fi
