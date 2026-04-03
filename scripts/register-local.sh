#!/bin/bash
# copilot-scheduler: Register a scheduled Copilot task in crontab
#
# Usage:
#   bash register-local.sh --cron "0 9 * * 1-5" --prompt "Fix lint errors" --name "daily-lint" [--notify log] [--working-dir /path]

set -euo pipefail

# --- Defaults ---
NOTIFY="log"
WORKING_DIR="$HOME"
SCHEDULER_DIR="$HOME/.copilot-scheduler"
LOG_DIR="${SCHEDULER_DIR}/logs"
LOCK_DIR="${SCHEDULER_DIR}/locks"
JOBS_DIR="${SCHEDULER_DIR}/jobs"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"
COPILOT_PATH="$(command -v copilot 2>/dev/null || echo "")"
NODE_BIN_DIR="$(dirname "${COPILOT_PATH:-/usr/bin/copilot}")"

# --- Parse Arguments ---
CRON=""
PROMPT=""
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cron)    CRON="$2";        shift 2 ;;
    --prompt)  PROMPT="$2";      shift 2 ;;
    --name)    NAME="$2";        shift 2 ;;
    --notify)  NOTIFY="$2";      shift 2 ;;
    --working-dir) WORKING_DIR="$2"; shift 2 ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      echo "Usage: register-local.sh --cron \"EXPR\" --prompt \"TEXT\" --name \"NAME\" [--notify log|issue|none] [--working-dir DIR]" >&2
      exit 1
      ;;
  esac
done

# --- Validate Required Arguments ---
if [ -z "$CRON" ] || [ -z "$PROMPT" ] || [ -z "$NAME" ]; then
  echo "Error: --cron, --prompt, and --name are required." >&2
  exit 1
fi

# --- Validate cron expression (5 fields) ---
FIELD_COUNT=$(echo "$CRON" | awk '{print NF}')
if [ "$FIELD_COUNT" -ne 5 ]; then
  echo "Error: Invalid cron expression '${CRON}'. Must have exactly 5 fields." >&2
  echo "Format: minute hour day-of-month month day-of-week" >&2
  exit 1
fi

# --- Validate name (alphanumeric + hyphens only) ---
if ! echo "$NAME" | grep -qE '^[a-zA-Z0-9_-]+$'; then
  echo "Error: Name '${NAME}' contains invalid characters. Use only alphanumeric, hyphens, and underscores." >&2
  exit 1
fi

# --- Check for duplicate ---
if [ -d "${JOBS_DIR}/${NAME}" ]; then
  echo "Error: Job '${NAME}' already exists. Use --name with a different name, or unregister first." >&2
  exit 1
fi

# --- Validate copilot CLI ---
if [ -z "$COPILOT_PATH" ]; then
  echo "Error: 'copilot' command not found in PATH." >&2
  exit 1
fi

# --- Validate working directory ---
if [ ! -d "$WORKING_DIR" ]; then
  echo "Error: Working directory '${WORKING_DIR}' does not exist." >&2
  exit 1
fi

# --- Create job directory ---
JOB_DIR="${JOBS_DIR}/${NAME}"
mkdir -p "$JOB_DIR" "$LOG_DIR" "$LOCK_DIR"

# --- Generate run.sh from template ---
TEMPLATE="${TEMPLATE_DIR}/cron-wrapper.sh.template"
if [ ! -f "$TEMPLATE" ]; then
  echo "Error: Template not found: ${TEMPLATE}" >&2
  exit 1
fi

RUN_SCRIPT="${JOB_DIR}/run.sh"
CREATED_AT="$(date --iso-8601=seconds)"

sed \
  -e "s|{{NAME}}|${NAME}|g" \
  -e "s|{{CRON}}|${CRON}|g" \
  -e "s|{{PROMPT}}|${PROMPT}|g" \
  -e "s|{{WORKING_DIR}}|${WORKING_DIR}|g" \
  -e "s|{{LOG_DIR}}|${LOG_DIR}|g" \
  -e "s|{{LOCK_DIR}}|${LOCK_DIR}|g" \
  -e "s|{{NOTIFY}}|${NOTIFY}|g" \
  -e "s|{{COPILOT_PATH}}|${COPILOT_PATH}|g" \
  -e "s|{{NODE_BIN_DIR}}|${NODE_BIN_DIR}|g" \
  -e "s|{{HOME}}|${HOME}|g" \
  -e "s|{{CREATED_AT}}|${CREATED_AT}|g" \
  -e "s|{{SCRIPT_DIR}}|${SCRIPT_DIR}|g" \
  "$TEMPLATE" > "$RUN_SCRIPT"

chmod +x "$RUN_SCRIPT"

# --- Save metadata ---
cat > "${JOB_DIR}/meta.json" <<METAEOF
{
  "name": "${NAME}",
  "cron": "${CRON}",
  "prompt": "${PROMPT}",
  "notify": "${NOTIFY}",
  "working_dir": "${WORKING_DIR}",
  "created_at": "${CREATED_AT}",
  "created_by": "copilot-scheduler"
}
METAEOF

# --- Register in crontab ---
CRON_ENTRY="${CRON} ${RUN_SCRIPT}"
CRON_COMMENT="# copilot-scheduler:${NAME}"

# Get current crontab (or empty if none)
CURRENT_CRONTAB="$(crontab -l 2>/dev/null || true)"

# Append new entry
NEW_CRONTAB="${CURRENT_CRONTAB}
${CRON_COMMENT}
${CRON_ENTRY}"

# Remove leading blank lines
NEW_CRONTAB="$(echo "$NEW_CRONTAB" | sed '/./,$!d')"

echo "$NEW_CRONTAB" | crontab -

echo "Successfully registered schedule '${NAME}':"
echo "  Cron:      ${CRON}"
echo "  Prompt:    ${PROMPT}"
echo "  Notify:    ${NOTIFY}"
echo "  Work Dir:  ${WORKING_DIR}"
echo "  Run Script: ${RUN_SCRIPT}"
echo ""
echo "Verify with: crontab -l | grep copilot-scheduler"
