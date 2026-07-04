#!/usr/bin/env bash
# session-close.sh — Session journaling for cross-session memory continuity
# Run at exit or heartbeat idle to persist context into daily + long-term memory.
#
# Usage:
#   ./scripts/session-close.sh              # uses default workspace
#   ./scripts/session-close.sh /path/to/ws  # explicit workspace root

set -euo pipefail

WORKSPACE="${1:-/root/.openclaw/workspace}"
MEMORY_DIR="$WORKSPACE/memory"
SESSION_LOG="$WORKSPACE/.session-log.md"
MEMORY_FILE="$WORKSPACE/MEMORY.md"
TRASH_DIR="$WORKSPACE/.trash"
DATE_STR=$(date +%Y-%m-%d)
DAILY_FILE="$MEMORY_DIR/$DATE_STR.md"
PRUNE_DAYS=30

mkdir -p "$MEMORY_DIR"
mkdir -p "$TRASH_DIR"

# ── 1. Aggregate today's journal into daily note ──────────────────────────
if [ -f "$SESSION_LOG" ] && [ -s "$SESSION_LOG" ]; then
    if [ -f "$DAILY_FILE" ]; then
        # Append only lines not already present (deduplicate)
        while IFS= read -r line; do
            if ! grep -qF "$line" "$DAILY_FILE" 2>/dev/null; then
                echo "$line" >> "$DAILY_FILE"
            fi
        done < "$SESSION_LOG"
    else
        # Write header + content for a fresh daily file
        {
            echo "# Session Journal — $DATE_STR"
            echo
            echo "_Auto-journaled at session close._"
            echo
            cat "$SESSION_LOG"
        } > "$DAILY_FILE"
    fi
    # Clear the session log for next run
    > "$SESSION_LOG"
fi

# Ensure daily file has at least a header if it's empty
if [ -f "$DAILY_FILE" ] && [ ! -s "$DAILY_FILE" ]; then
    cat > "$DAILY_FILE" <<- DAILY_EOF
	# Session Journal — $DATE_STR

	_Auto-journaled at session close. No significant entries recorded._
	DAILY_EOF
fi

# ── 2. Merge significant entries into long-term MEMORY.md ────────────────
if [ -f "$DAILY_FILE" ] && [ -s "$DAILY_FILE" ]; then
    # Extract lines tagged as significant decisions, milestones, or lessons
    SIGNIFICANT=$(grep -iE '^(## |\*DECISION:|\*LESSON:|\*MILESTONE:|\*REMEMBER:|✏️|📌|🔑)' "$DAILY_FILE" || true)
    if [ -n "$SIGNIFICANT" ]; then
        {
            echo ""
            echo "---"
            echo "## Merged from $DATE_STR"
            echo ""
            echo "$SIGNIFICANT"
        } >> "$MEMORY_FILE"
    fi
fi

# ── 3. Prune daily notes older than PRUNE_DAYS ───────────────────────────
find "$MEMORY_DIR" -name '????-??-??.md' -mtime +"$PRUNE_DAYS" | while IFS= read -r old_file; do
    mv "$old_file" "$TRASH_DIR/"
done 2>/dev/null || true

# ── 4. Git-commit both MEMORY.md and memory/ changes ─────────────────────
if command -v git >/dev/null 2>&1 && [ -d "$WORKSPACE/.git" ]; then
    cd "$WORKSPACE"
    git add "$MEMORY_FILE" "$MEMORY_DIR/" 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "session-close: journal $DATE_STR" --quiet 2>/dev/null || true
    fi
fi
