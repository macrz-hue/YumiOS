#!/bin/bash
set -euo pipefail

WORKSPACE="${1:-/root/.openclaw/workspace}"
MEMORY_DIR="$WORKSPACE/memory"
SESSION_LOG="$WORKSPACE/.session-log.md"
DAILY_FILE="$MEMORY_DIR/$(date +%Y-%m-%d).md"
PRUNE_DAYS=30

mkdir -p "$MEMORY_DIR"

# ── 1. Collect recent file writes (newer than the session log) ───────────
DIFF_ENTRY=""
TMPDIFF=$(mktemp)
find "$WORKSPACE" -maxdepth 3 -type f -newer "$SESSION_LOG" 2>/dev/null \
  ! -path "$WORKSPACE/.git/*" \
  ! -path "$WORKSPACE/memory/*" \
  ! -name ".session-*" \
  -printf '%T@ %p\n' | sort -rn | head -30 > "$TMPDIFF"

if [ -s "$TMPDIFF" ]; then
  DIFF_ENTRY=$(while IFS=' ' read -r ts path; do
    rel="${path#$WORKSPACE/}"
    echo "  - \`$rel\`"
  done < "$TMPDIFF")
fi
rm -f "$TMPDIFF"

# ── 2. Build structured daily entry ─────────────────────────────────────
DATE_STR=$(date +%Y-%m-%d)
TIME_STR=$(date +%H:%M:%S" %Z")
ENTRY=$(mktemp)

cat > "$ENTRY" << ENTRIES
## Session Close — $DATE_STR

_Closed at $TIME_STR._

ENTRIES

if [ -s "$SESSION_LOG" ]; then
  cat >> "$ENTRY" << ENTRIES
### Session Log

$(cat "$SESSION_LOG")

ENTRIES
fi

if [ -n "$DIFF_ENTRY" ]; then
  cat >> "$ENTRY" << ENTRIES
### Recent File Changes

$DIFF_ENTRY

ENTRIES
fi

# ── 3. Append to daily file (deduplicate lines) ─────────────────────────
if [ ! -f "$DAILY_FILE" ]; then
  {
    echo "# Session Journal — $DATE_STR"
    echo
    cat "$ENTRY"
  } > "$DAILY_FILE"
else
  while IFS= read -r line; do
    if ! grep -qFx "$line" "$DAILY_FILE" 2>/dev/null; then
      echo "$line" >> "$DAILY_FILE"
    fi
  done < "$ENTRY"
fi
rm -f "$ENTRY"

# ── 4. Clear session log after successful write ─────────────────────────
if [ -f "$SESSION_LOG" ]; then
  > "$SESSION_LOG"
fi

# ── 5. Prune daily notes older than PRUNE_DAYS ───────────────────────────
mkdir -p "$WORKSPACE/.session-trash"
find "$MEMORY_DIR" -name '????-??-??.md' -mtime +"$PRUNE_DAYS" -exec mv {} "$WORKSPACE/.session-trash/" \; 2>/dev/null || true

# ── 6. Git-track memory changes if repo exists ──────────────────────────
if command -v git >/dev/null 2>&1 && git -C "$WORKSPACE" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$WORKSPACE" add "$MEMORY_DIR/" 2>/dev/null || true
  if ! git -C "$WORKSPACE" diff --cached --quiet 2>/dev/null; then
    git -C "$WORKSPACE" commit -m "session-close: journal $DATE_STR" --quiet 2>/dev/null || true
  fi
fi
