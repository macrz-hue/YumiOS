#!/bin/bash
# corrections.sh — Yumehiru's learning system
# Logs corrections and applies them as default behavior.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)/../corrections"
DB="$DIR/corrections.yaml"
AGENTS="/root/.openclaw/workspace/AGENTS.md"
LOCK_FILE="$DIR/.corrections.lock"

log() { echo "[corrections] $(date -u +%H:%M:%S) $*"; }

if ! mkdir "$LOCK_FILE" 2>/dev/null; then log "already running"; exit 0; fi
trap 'rm -rf "$LOCK_FILE"' EXIT

ensure_db() {
  if [ ! -f "$DB" ] || [ ! -s "$DB" ]; then echo "[]" > "$DB"; fi
}

next_id() {
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
ids = [e.get('id', 0) for e in entries]
print(max(ids) + 1 if ids else 1)
"
}

cmd_log() {
  local trigger="${1:-}"
  local correction="${2:-}"
  if [ -z "$trigger" ] || [ -z "$correction" ]; then
    echo "Usage: corrections log <trigger/what-was-wrong> <correction/what-to-do-instead> [--apply]"
    exit 1
  fi
  local apply=false
  [[ "${3:-}" == "--apply" ]] && apply=true
  ensure_db
  local id=$(next_id)
  local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
entries.append({
    'id': $id,
    'timestamp': '$ts',
    'trigger': $(echo "$trigger" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'correction': $(echo "$correction" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'applied': True
})
with open('$DB', 'w') as f:
    json.dump(entries, f, indent=2)
print(f'Logged correction #$id')
"
  $apply && cmd_apply "$id"
}

cmd_list() {
  ensure_db
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
if not entries:
    print('No corrections logged.')
    exit(0)
print('ID  APPLIED  DATE                TRIGGER')
print('-'*60)
for e in entries:
    a = '✅' if e.get('applied') else '⏳'
    t = e.get('timestamp','')[:16]
    trig = e.get('trigger','')[:40]
    print(f\"{e.get('id','?'):<4} {a:<8} {t:<20} {trig}\")
"
}

cmd_apply() {
  local id="${1:-}"
  [ -z "$id" ] && echo "Usage: corrections apply <id>" && exit 1
  ensure_db
  
  # Get the correction
  local entry=$(python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
for e in entries:
    if e.get('id') == $id:
        print(json.dumps(e))
        exit(0)
print('{}')
")
  
  if [ "$entry" = "{}" ]; then
    echo "Correction #$id not found"
    exit 1
  fi
  
  local correction=$(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('correction',''))")
  
  # Mark as applied in DB
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
for e in entries:
    if e.get('id') == $id:
        e['applied'] = True
with open('$DB', 'w') as f:
    json.dump(entries, f, indent=2)
print('Applied correction #$id')
"
  
  # Append to AGENTS.md as a learned rule
  if [ -f "$AGENTS" ]; then
    local rule="# 🔁 Learned from correction #$id: $correction"
    if ! grep -q "correction #$id" "$AGENTS" 2>/dev/null; then
      echo "" >> "$AGENTS"
      echo "$rule" >> "$AGENTS"
      echo "[corrections] Wired correction #$id into AGENTS.md"
    fi
  fi
  
  # Also save to memory for cross-session persistence
  local memory_dir="/root/.openclaw/workspace/memory"
  mkdir -p "$memory_dir"
  local date_file="$memory_dir/corrections.md"
  {
    echo "## Correction #$id ($(date -u +%Y-%m-%d))"
    echo "- **Trigger:** $(echo "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin).get('trigger',''))")"
    echo "- **Correction:** $correction"
    echo "- **Applied:** $(date -u)"
    echo ""
  } >> "$date_file"
  echo "[corrections] Saved to memory/corrections.md"
}

cmd_read() {
  # Called on startup — reads all applied corrections and returns them
  ensure_db
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
applied = [e for e in entries if e.get('applied')]
if not applied:
    print('No applied corrections.')
else:
    print(f'=== {len(applied)} Learned Corrections ===')
    for e in applied:
        print(f\"  #{e['id']}: {e.get('correction','')[:100]}\")
"
}

cmd_show() {
  local id="${1:-}"
  [ -z "$id" ] && echo "Usage: corrections show <id>" && exit 1
  ensure_db
  python3 -c "
import json
with open('$DB') as f:
    entries = json.load(f)
for e in entries:
    if e.get('id') == $id:
        print(f\"ID:       #{e['id']}\")
        print(f\"Date:     {e.get('timestamp','')}\")
        print(f\"Trigger:  {e.get('trigger','')}\")
        print(f\"Correct:  {e.get('correction','')}\")
        print(f\"Applied:  {'✅' if e.get('applied') else '⏳'}\")
        exit(0)
print(f'Correction #$id not found')
"
}

# Main
CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  log)    cmd_log "$@" ;;
  list|ls) cmd_list ;;
  apply)  cmd_apply "$@" ;;
  show)   cmd_show "$@" ;;
  read)   cmd_read ;;
  *)
    echo "Usage: corrections {log|list|show|apply|read}"
    echo "  log <trigger> <correction> [--apply]  — Log a correction"
    echo "  list                                   — Show all corrections"
    echo "  show <id>                              — Show details"
    echo "  apply <id>                             — Apply as default behavior"
    echo "  read                                   — Read applied corrections"
    ;;
esac
