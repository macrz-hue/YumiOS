#!/bin/bash
# session-close.sh — Journal session context into daily memory notes
# 
# Captures recent file writes, logged decisions, and errors into a
# structured daily note at memory/YYYY-MM-DD.md.  Prunes daily notes
# older than 30 days.
#
# Call on: heartbeat idle, session exit, or manually:
#   ./scripts/session-close.sh

set -euo pipefail

WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
DATE="$(date +%Y-%m-%d)"
DAILY="${WORKSPACE}/memory/${DATE}.md"
SESSION_LOG="${WORKSPACE}/.session-log.md"
PRUNE_DAYS=30

mkdir -p "${WORKSPACE}/memory"

# ── Ensure daily file exists with header ────────────────────────────
if [ ! -f "${DAILY}" ]; then
  cat > "${DAILY}" <<- HEADER
# ${DATE} — Daily Notes

## Decisions

## File Writes

## Errors / Blockers

## Session Summary

HEADER
  echo "[session-close] Created ${DAILY}"
fi

# ── Append session scratch log, if present ──────────────────────────
if [ -f "${SESSION_LOG}" ]; then
  {
    echo ""
    echo "---"
    echo "## Session Log ($(date -u '+%H:%M UTC'))"
    cat "${SESSION_LOG}"
  } >> "${DAILY}"
  rm -f "${SESSION_LOG}"
  echo "[session-close] Appended .session-log.md to ${DAILY}"
fi

# ── Git: recent file writes ─────────────────────────────────────────
if git -C "${WORKSPACE}" rev-parse --git-dir >/dev/null 2>&1; then
  RECENT="$(git -C "${WORKSPACE}" diff --name-only HEAD~1..HEAD 2>/dev/null || true)"
  if [ -n "${RECENT}" ]; then
    {
      echo ""
      echo "### Files changed in last commit"
      echo "${RECENT}"
    } >> "${DAILY}"
    echo "[session-close] Logged recent file changes"
  fi
fi

# ── Task status snapshot ────────────────────────────────────────────
TASK_FILE="${WORKSPACE}/tasks/tasks.yaml"
if [ -f "${TASK_FILE}" ]; then
  python3 -c "
import json
with open('${TASK_FILE}') as f:
    tasks = json.load(f)
active = [t for t in tasks if t.get('status') in ('active', 'pending')]
if active:
    print('')
    print('### Active Tasks')
    for t in sorted(active, key=lambda x: x.get('id', 0)):
        print(f\"- [#{t['id']}] {t['title']} ({t.get('status','')})\")
" >> "${DAILY}" 2>/dev/null || true
fi

# ── Prune old notes ─────────────────────────────────────────────────
find "${WORKSPACE}/memory" -name "*.md" -mtime +${PRUNE_DAYS} -exec rm -f {} \; 2>/dev/null || true
echo "[session-close] Pruned daily notes older than ${PRUNE_DAYS} days"

# ── Long-term summary: merge into MEMORY.md ─────────────────────────
# Only if there are significant changes (decisions or errors logged)
if grep -q "^## Decisions\|^## Errors" "${DAILY}" 2>/dev/null; then
  echo "[session-close] Daily note has decisions/errors — ready for MEMORY.md merge"
fi

echo "[session-close] ✅ Journaled to ${DAILY}"
