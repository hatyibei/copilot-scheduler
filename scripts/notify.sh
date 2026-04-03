#!/bin/bash
# copilot-scheduler: Send notification for task execution result
#
# Usage:
#   bash notify.sh --name "task-name" --log-file "/path/to/log" --method issue

set -euo pipefail

NAME=""
LOG_FILE=""
METHOD="log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="$2";     shift 2 ;;
    --log-file) LOG_FILE="$2"; shift 2 ;;
    --method)   METHOD="$2";   shift 2 ;;
    *)          shift ;;
  esac
done

if [ -z "$NAME" ] || [ -z "$LOG_FILE" ]; then
  echo "Error: --name and --log-file are required." >&2
  exit 1
fi

case "$METHOD" in
  log)
    echo "[copilot-scheduler] ${NAME}: Log saved to ${LOG_FILE}"
    ;;

  issue)
    if ! command -v gh &>/dev/null; then
      echo "Error: 'gh' CLI not found. Cannot create GitHub Issue." >&2
      exit 1
    fi

    # Get repo from current git context or meta.json
    REPO=""
    SCHEDULER_DIR="$HOME/.copilot-scheduler"
    META_FILE="${SCHEDULER_DIR}/jobs/${NAME}/meta.json"
    if [ -f "$META_FILE" ]; then
      REPO=$(grep -o '"repo": *"[^"]*"' "$META_FILE" 2>/dev/null | sed 's/"repo": *"//;s/"$//' || true)
    fi

    if [ -z "$REPO" ]; then
      REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    fi

    if [ -z "$REPO" ]; then
      echo "Error: Cannot determine repository. Set 'repo' in meta.json or run from a git repo." >&2
      exit 1
    fi

    # Read log tail (last 100 lines, max 3000 chars)
    LOG_CONTENT=$(tail -100 "$LOG_FILE" | head -c 3000)
    TODAY=$(date +%Y-%m-%d)

    gh issue create \
      --repo "$REPO" \
      --title "[copilot-scheduler] ${NAME} - ${TODAY}" \
      --body "$(cat <<EOF
## Scheduled Task Result

**Task**: ${NAME}
**Date**: ${TODAY}
**Log**: \`${LOG_FILE}\`

\`\`\`
${LOG_CONTENT}
\`\`\`
EOF
)"

    echo "[copilot-scheduler] ${NAME}: Issue created in ${REPO}"
    ;;

  none)
    # No notification
    ;;

  *)
    echo "Error: Unknown notification method: ${METHOD}" >&2
    exit 1
    ;;
esac
