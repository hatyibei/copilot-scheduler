#!/bin/bash
# copilot-scheduler: Generate a GitHub Actions workflow for scheduled Copilot tasks
#
# Usage:
#   bash register-actions.sh --cron "0 9 * * 1-5" --prompt "Run tests" --name "daily-test" [--notify log|issue] [--output-dir .github/workflows]

set -euo pipefail

NOTIFY="log"
OUTPUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "${SCRIPT_DIR}/../templates" && pwd)"

# --- Parse Arguments ---
CRON=""
PROMPT=""
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cron)       CRON="$2";       shift 2 ;;
    --prompt)     PROMPT="$2";     shift 2 ;;
    --name)       NAME="$2";       shift 2 ;;
    --notify)     NOTIFY="$2";     shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate ---
if [ -z "$CRON" ] || [ -z "$PROMPT" ] || [ -z "$NAME" ]; then
  echo "Error: --cron, --prompt, and --name are required." >&2
  exit 1
fi

FIELD_COUNT=$(echo "$CRON" | awk '{print NF}')
if [ "$FIELD_COUNT" -ne 5 ]; then
  echo "Error: Invalid cron expression '${CRON}'. Must have exactly 5 fields." >&2
  exit 1
fi

# --- Determine output directory ---
if [ -z "$OUTPUT_DIR" ]; then
  # Try to find .github/workflows in current repo
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$GIT_ROOT" ]; then
    OUTPUT_DIR="${GIT_ROOT}/.github/workflows"
  else
    OUTPUT_DIR=".github/workflows"
  fi
fi

mkdir -p "$OUTPUT_DIR"

# --- Set notify flag ---
NOTIFY_ISSUE="false"
if [ "$NOTIFY" = "issue" ]; then
  NOTIFY_ISSUE="true"
fi

# --- Generate workflow from template ---
TEMPLATE="${TEMPLATE_DIR}/actions-workflow.yml.template"
if [ ! -f "$TEMPLATE" ]; then
  echo "Error: Template not found: ${TEMPLATE}" >&2
  exit 1
fi

CREATED_AT="$(date --iso-8601=seconds)"
OUTPUT_FILE="${OUTPUT_DIR}/copilot-sched-${NAME}.yml"

sed \
  -e "s|{{NAME}}|${NAME}|g" \
  -e "s|{{CRON}}|${CRON}|g" \
  -e "s|{{PROMPT}}|${PROMPT}|g" \
  -e "s|{{NOTIFY_ISSUE}}|${NOTIFY_ISSUE}|g" \
  -e "s|{{CREATED_AT}}|${CREATED_AT}|g" \
  "$TEMPLATE" > "$OUTPUT_FILE"

echo "Generated workflow: ${OUTPUT_FILE}"
echo ""
echo "Next steps:"
echo "  1. Review the generated file"
echo "  2. Commit and push to your repository"
echo "  3. Set COPILOT_TOKEN secret in repo settings (if needed)"
echo ""
echo "To test manually:"
echo "  gh workflow run 'copilot-scheduler: ${NAME}'"
