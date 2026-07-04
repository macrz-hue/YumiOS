#!/bin/bash
# taskctl.sh — Yumehiru Task Manager
# Manages persistent task tracking via tasks/tasks.yaml
set -euo pipefail

TASKS_FILE="/root/.openclaw/workspace/tasks/tasks.yaml"
ARCHIVE_DIR="/root/.openclaw/workspace/tasks/archive"
mkdir -p "$(dirname "$TASKS_FILE")" "$ARCHIVE_DIR"

# Ensure file exists
[ -f "$TASKS_FILE" ] || echo "[]" > "$TASKS_FILE"

usage() {
  echo "Usage: taskctl.sh <command> [args]"
  echo "  list [status]    — List tasks (optional: pending|active|blocked|done)"
  echo "  add <title>      — Create a new task (opens editor for details)"
  echo "  add-quick <title> [priority] [tags] — Quick-add a task"
  echo "  get <id>         — Show task details"
  echo "  start <id>       — Move task to active"
  echo "  done <id>        — Mark task complete and archive"
  echo "  block <id> <reason> — Mark task blocked"
  echo "  unblock <id>     — Return blocked task to pending"
  echo "  next             — Show highest priority pending task"
  echo "  priority <id> <high|medium|low> — Set priority"
  echo "  tag <id> <tag>   — Add a tag"
  echo "  note <id> <text> — Add a note"
  echo "  cleanup          — Archive done tasks older than 7 days"
  exit 1
}

next_id() {
  python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
ids = [t.get('id', 0) for t in tasks]
print(max(ids) + 1 if ids else 1)
"
}

save_tasks() {
  python3 -c "
import json
tasks = $1
with open('$TASKS_FILE', 'w') as f:
    json.dump(tasks, f, indent=2)
"
}

get_tasks() {
  python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
status_filter = '$1'
if status_filter:
    tasks = [t for t in tasks if t.get('status') == status_filter]
print(json.dumps(tasks))
"
}

CMD="${1:-help}"
shift 2>/dev/null || true

case "$CMD" in
  list)
    FILTER="${1:-}"
    get_tasks "$FILTER" | python3 -c "
import json,sys
tasks = json.load(sys.stdin)
if not tasks:
    print('No tasks.')
    sys.exit(0)
# Sort: high first, then medium, then low
priority_order = {'high': 0, 'medium': 1, 'low': 2}
tasks.sort(key=lambda t: (priority_order.get(t.get('priority','low'), 99), t.get('id',0)))
print(f\"{'ID':<4} {'STATUS':<10} {'PRIORITY':<10} TITLE\")
print('-'*70)
for t in tasks:
    print(f\"{t.get('id',''):<4} {t.get('status',''):<10} {t.get('priority',''):<10} {t.get('title','')[:50]}\")
"
    ;;
  
  next)
    # Show next actionable task (active first, then pending)
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
priority_order = {'high': 0, 'medium': 1, 'low': 2}
# Check active first
tasks.sort(key=lambda t: (0 if t.get('status')=='active' else 1, priority_order.get(t.get('priority','low'), 99), t.get('id',0)))
for t in tasks:
    if t.get('status') in ('active', 'pending'):
        print(f\"Next: [#{t['id']}] {t['title']} ({t.get('status','')}, {t.get('priority','medium')})\")
        exit(0)
print('No tasks to work on.')
"
    ;;
  
  add)
    TITLE="${1:-}"
    [ -z "$TITLE" ] && echo "Usage: taskctl.sh add <title>" && exit 1
    ID=$(next_id)
    PRIORITY="${2:-medium}"
    TAGS="${3:-general}"
    TAGS_JSON=$(echo "$TAGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip().split(',')))")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
tasks.append({
    'id': $ID,
    'title': $(echo "$TITLE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'status': 'pending',
    'priority': $(echo "$PRIORITY" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'created': '$TIMESTAMP',
    'updated': '$TIMESTAMP',
    'source': 'manual',
    'tags': $TAGS_JSON,
    'notes': ''
})
with open('$TASKS_FILE', 'w') as f:
    json.dump(tasks, f, indent=2)
print('Created task #$ID')
"
    ;;
  
  add-quick)
    TITLE="${1:-}"
    PRIORITY="${2:-medium}"
    TAGS="${3:-general}"
    shift 3 2>/dev/null
    ID=$(next_id)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
tasks.append({
    'id': $ID,
    'title': $(echo "$TITLE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'status': 'pending',
    'priority': $(echo "$PRIORITY" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'created': '$TIMESTAMP',
    'updated': '$TIMESTAMP',
    'source': 'quick-add',
    'tags': [$(for t in $(echo "$TAGS" | tr ',' ' '); do echo -n "\"$t\","; done | sed 's/,$//')],
    'notes': ''
})
with open('$TASKS_FILE', 'w') as f:
    json.dump(tasks, f, indent=2)
print('Created task #$ID')
"
    echo "Added: #$ID - $TITLE"
    ;;
  
  get)
    ID="${1:-}"
    [ -z "$ID" ] && echo "Usage: taskctl.sh get <id>" && exit 1
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
for t in tasks:
    if t.get('id') == $ID:
        for k,v in t.items():
            print(f'{k}: {json.dumps(v) if isinstance(v,str) else v}')
        exit(0)
print(f'Task #$ID not found')
" 2>/dev/null || echo "Task #$ID not found"
    ;;
  
  start|done|unblock)
    ID="${1:-}"
    [ "$CMD" = "start" ] && NEW_STATUS="active" || NEW_STATUS="$CMD"
    [ "$CMD" = "done" ] && NEW_STATUS="done"
    [ "$CMD" = "unblock" ] && NEW_STATUS="pending"
    [ -z "$ID" ] && echo "Usage: taskctl.sh $CMD <id>" && exit 1
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
for t in tasks:
    if t.get('id') == $ID:
        t['status'] = '$NEW_STATUS'
        t['updated'] = '$TIMESTAMP'
        if '$NEW_STATUS' == 'done':
            t['completed'] = '$TIMESTAMP'
        with open('$TASKS_FILE', 'w') as f:
            json.dump(tasks, f, indent=2)
        print(f'Task #$ID → $NEW_STATUS')
        exit(0)
print(f'Task #$ID not found')
"
    ;;
  
  block)
    ID="${1:-}"
    REASON="${2:-no reason given}"
    [ -z "$ID" ] && echo "Usage: taskctl.sh block <id> <reason>" && exit 1
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
for t in tasks:
    if t.get('id') == $ID:
        t['status'] = 'blocked'
        t['updated'] = '$TIMESTAMP'
        t['blocked_reason'] = $(echo "$REASON" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")
        with open('$TASKS_FILE', 'w') as f:
            json.dump(tasks, f, indent=2)
        print(f'Task #$ID → blocked: $REASON')
        exit(0)
print(f'Task #$ID not found')
"
    ;;
  
  priority)
    ID="${1:-}"
    PRIORITY="${2:-medium}"
    [ -z "$ID" ] && echo "Usage: taskctl.sh priority <id> <high|medium|low>" && exit 1
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
for t in tasks:
    if t.get('id') == $ID:
        t['priority'] = '$PRIORITY'
        t['updated'] = '$TIMESTAMP'
        with open('$TASKS_FILE', 'w') as f:
            json.dump(tasks, f, indent=2)
        print(f'Task #$ID priority → $PRIORITY')
        exit(0)
print(f'Task #$ID not found')
"
    ;;
  
  note)
    ID="${1:-}"
    NOTE="${2:-}"
    [ -z "$ID" ] && echo "Usage: taskctl.sh note <id> <text>" && exit 1
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
for t in tasks:
    if t.get('id') == $ID:
        old = t.get('notes', '')
        t['notes'] = (old + '\\n' if old else '') + '[$TIMESTAMP] $NOTE'
        t['updated'] = '$TIMESTAMP'
        with open('$TASKS_FILE', 'w') as f:
            json.dump(tasks, f, indent=2)
        print(f'Note added to #$ID')
        exit(0)
print(f'Task #$ID not found')
"
    ;;
  
  cleanup)
    python3 -c "
import json, shutil, os
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
archive = [t for t in tasks if t.get('status') == 'done']
active = [t for t in tasks if t.get('status') != 'done']
if archive:
    with open('$TASKS_FILE', 'w') as f:
        json.dump(active, f, indent=2)
    with open('$ARCHIVE_DIR/archived-$(date +%Y%m%d).json', 'w') as f:
        json.dump(archive, f, indent=2)
    print(f'Archived {len(archive)} completed tasks')
else:
    print('No completed tasks to archive')
"
    ;;
  
  from-suggestion)
    # Called by the executor to convert a suggestion into a task
    FILE="${1:-}"
    [ ! -f "$FILE" ] && echo "File not found: $FILE" && exit 1
    
    ID=$(next_id)
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TITLE=$(grep '^title:' "$FILE" | sed 's/^title: *//' | sed 's/^"//;s/"$//')
    TARGET=$(grep '^target:' "$FILE" | sed 's/^target: *//' | sed 's/^"//;s/"$//')
    
    python3 -c "
import json
with open('$TASKS_FILE') as f:
    tasks = json.load(f)
tasks.append({
    'id': $ID,
    'title': $(echo "$TITLE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"),
    'status': 'pending',
    'priority': 'medium',
    'created': '$TIMESTAMP',
    'updated': '$TIMESTAMP',
    'source': 'idea-generator',
    'tags': ['suggestion', $(echo "$TARGET" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")],
    'notes': $(python3 -c "
import json
with open('$FILE') as f:
    content = f.read()
print(json.dumps(content))
")
})
with open('$TASKS_FILE', 'w') as f:
    json.dump(tasks, f, indent=2)
print($ID)
"
    ;;
  
  help|*)
    usage
    ;;
esac
