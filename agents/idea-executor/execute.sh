#!/bin/bash
# Idea Executor — Implementation Loop + Task Worker
# Picks highest priority pending task, implements it, marks done.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GEN_DIR="$DIR/../idea-generator"
STATE_FILE="$DIR/state/processed.md"
LOGS_DIR="$DIR/logs"
LOCK_FILE="$DIR/.executor.lock"
SUGGESTION_FILE="$GEN_DIR/state/latest-suggestion.md"
GEN_STATE_FILE="$GEN_DIR/state/current.md"
LLM_URL="http://127.0.0.1:18080/v1/chat/completions"
TOOL_URL="http://127.0.0.1:18081"
TASKCTL="/root/.openclaw/workspace/scripts/taskctl.sh"
TASKS_FILE="/root/.openclaw/workspace/tasks/tasks.yaml"

log() { echo "[idea-executor] $(date -u +%H:%M:%S) $*"; }

if ! mkdir "$LOCK_FILE" 2>/dev/null; then log "already running"; exit 0; fi
trap 'rm -rf "$LOCK_FILE"' EXIT

# Check server
if ! curl -sf "http://127.0.0.1:18080/health" >/dev/null 2>&1; then
  log "ERROR: LLM server not running"
  exit 1
fi

# STEP 1: Check for pending tasks first
log "checking task list..."
NEXT_TASK=$($TASKCTL next 2>/dev/null | grep '^Next:' | sed 's/^Next: \[#//;s/\].*//' || echo "")

if [ -n "$NEXT_TASK" ]; then
  log "found pending task #$NEXT_TASK"
  # Get task details
  TASK_TITLE=$($TASKCTL get "$NEXT_TASK" 2>/dev/null | grep '^title:' | cut -d' ' -f2-)
  TASK_NOTES=$($TASKCTL get "$NEXT_TASK" 2>/dev/null | grep '^notes:' | cut -d' ' -f2-)
  log "task: $TASK_TITLE"
  
  # Mark as active
  $TASKCTL start "$NEXT_TASK" 2>/dev/null || true
  log "task #$NEXT_TASK → active"
  
  # Generate and execute implementation
  SUGGESTION_TEXT="Task #$NEXT_TASK: $TASK_TITLE"
  [ -n "$TASK_NOTES" ] && SUGGESTION_TEXT="$SUGGESTION_TEXT\n\nContext: $TASK_NOTES"
  
  log "generating implementation script from task #$NEXT_TASK..."
else
  # STEP 2: No pending tasks — check for new suggestions from generator
  log "no pending tasks, checking for new suggestions..."
  
  if [ ! -f "$SUGGESTION_FILE" ]; then log "nothing to do"; exit 0; fi
  
  # Read processed state
  LAST_PROCESSED=$(grep 'last_processed_id:' "$STATE_FILE" | awk '{print $2}')
  LAST_PROCESSED=${LAST_PROCESSED:-null}
  SUGGESTION_ID=$(grep '^suggestion_id:' "$SUGGESTION_FILE" | awk '{print $2}')
  
  if [ "$SUGGESTION_ID" = "$LAST_PROCESSED" ] || [ -z "$SUGGESTION_ID" ]; then
    log "no new suggestions"; exit 0
  fi
  
  log "processing new suggestion #$SUGGESTION_ID"
  SUGGESTION_TEXT=$(cat "$SUGGESTION_FILE")
  NEXT_TASK="suggestion-$SUGGESTION_ID"
fi

# Check consecutive failures
CONSECUTIVE_FAILS=$(grep 'consecutive_failures:' "$STATE_FILE" 2>/dev/null | awk '{print $2}')
CONSECUTIVE_FAILS=${CONSECUTIVE_FAILS:-0}
FAILURE_COUNT=$(grep 'failure_count:' "$STATE_FILE" 2>/dev/null | awk '{print $2}')
FAILURE_COUNT=${FAILURE_COUNT:-0}

if [ "$CONSECUTIVE_FAILS" -ge 3 ]; then
  log "3 consecutive failures, blocking"
  [ "$NEXT_TASK" != "suggestion-"* ] && $TASKCTL block "$NEXT_TASK" "3 consecutive failures" 2>/dev/null || true
  exit 1
fi

# Generate implementation via LLM with tool loop
SYSTEM_PROMPT="You are the Idea Executor. Given an improvement suggestion or task, write a bash script that implements it. Output ONLY a bash script — no explanation, no markdown wrapping. Use absolute paths rooted at /root/.openclaw/workspace. Safe operations only: mkdir, cat > file, cp, mv, sed, git. NO rm -rf, NO destructive changes. Each file must have inline content via heredoc (cat > path << 'EOF'). Always create parent dirs first with mkdir -p. If unsafe or vague, output: '# SKIP: reason'.

Tools available (return TOOL: tool_name | args to use):
- TOOL: web_search | <query>
- TOOL: run_python | <python code>
- TOOL: fetch_url | <url>"

MESSAGES=$(python3 << PYEOF
import json
msgs = [
    {"role": "system", "content": $(echo "$SYSTEM_PROMPT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")},
    {"role": "user", "content": $(echo "$SUGGESTION_TEXT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")}
]
print(json.dumps(msgs))
PYEOF
)

MAX_ROUNDS=3
for ((round=0; round<MAX_ROUNDS; round++)); do
  RAW=$(curl -s "$LLM_URL" -H "Content-Type: application/json" \
    -d "$(python3 << PYEOF
import json
msgs = json.loads($(echo "$MESSAGES" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"))
print(json.dumps({"messages": msgs, "max_tokens": 2048, "temperature": 0.5}))
PYEOF
)" 2>/dev/null)

  SCRIPT_TEXT=$(echo "$RAW" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)['choices'][0]['message']['content'])
except: print('PARSE_ERROR')
" 2>/dev/null)

  [ -z "$SCRIPT_TEXT" ] || [ "$SCRIPT_TEXT" = "PARSE_ERROR" ] && { log "bad response"; exit 1; }

  # Check for tool call
  TOOL_LINE=$(echo "$SCRIPT_TEXT" | grep '^TOOL:' | head -1)
  [ -z "$TOOL_LINE" ] && break

  log "tool: $TOOL_LINE"
  TOOL_NAME=$(echo "$TOOL_LINE" | sed 's/^TOOL: *//' | cut -d'|' -f1 | xargs)
  TOOL_ARGS=$(echo "$TOOL_LINE" | sed 's/^TOOL: *//' | cut -d'|' -f2- | xargs)

  TOOL_RESULT=""
  case "$TOOL_NAME" in
    web_search) TOOL_RESULT=$(curl -s "$TOOL_URL/web_search" -H "Content-Type: application/json" \
      -d "$(python3 -c "import json; print(json.dumps({'query': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"), 'max': 5}))")") ;;
    run_python) TOOL_RESULT=$(curl -s "$TOOL_URL/run_python" -H "Content-Type: application/json" \
      -d "$(python3 -c "import json; print(json.dumps({'code': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}))")") ;;
    fetch_url) TOOL_RESULT=$(curl -s "$TOOL_URL/fetch" -H "Content-Type: application/json" \
      -d "$(python3 -c "import json; print(json.dumps({'url': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}))")") ;;
  esac
  [ -z "$TOOL_RESULT" ] && TOOL_RESULT='{"error":"empty"}'

  MESSAGES=$(python3 << PYEOF
import json
msgs = json.loads($(echo "$MESSAGES" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"))
msgs.append({"role": "assistant", "content": $(echo "$SCRIPT_TEXT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")})
msgs.append({"role": "tool", "content": $(echo "$TOOL_RESULT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")})
print(json.dumps(msgs))
PYEOF
)
done

# Check for skip
if echo "$SCRIPT_TEXT" | grep -q "^# SKIP:"; then
  REASON=$(echo "$SCRIPT_TEXT" | sed 's/^# SKIP: //')
  log "Skipping: $REASON"
  [ "$NEXT_TASK" != "suggestion-"* ] && $TASKCTL block "$NEXT_TASK" "$REASON" 2>/dev/null || true
  exit 0
fi

# Extract and execute script
SCRIPT_FILE=$(mktemp)
echo "$SCRIPT_TEXT" | sed -n '/```bash/,/```/{//d;p}; /```sh/,/```/{//d;p}' > "$SCRIPT_FILE"
[ ! -s "$SCRIPT_FILE" ] && echo "$SCRIPT_TEXT" > "$SCRIPT_FILE"
if ! head -1 "$SCRIPT_FILE" | grep -q '^#!/'; then
  sed -i '1i #!/bin/bash\nset -euo pipefail' "$SCRIPT_FILE"
fi
chmod +x "$SCRIPT_FILE"
cp "$SCRIPT_FILE" "$LOGS_DIR/script-$(date +%s).sh"

log "executing implementation script..."
EXEC_LOG="$LOGS_DIR/exec-$(date +%s).log"
echo "# Executing" > "$EXEC_LOG"
date -u >> "$EXEC_LOG"

set +e
bash "$SCRIPT_FILE" >> "$EXEC_LOG" 2>&1
EXIT_CODE=$?
set -e
rm -f "$SCRIPT_FILE"
echo "EXIT: $EXIT_CODE" >> "$EXEC_LOG"

if [ "$EXIT_CODE" -eq 0 ]; then
  log "✅ Implementation successful"
  
  if [ "$NEXT_TASK" = "suggestion-"* ]; then
    # Suggestion from generator — mark processed and convert to task
    SUGGESTION_ID=$(echo "$NEXT_TASK" | sed 's/suggestion-//')
    cat > "$STATE_FILE" << ENDSTATE
last_processed_id: $SUGGESTION_ID
last_result: success
failure_count: "$FAILURE_COUNT"
consecutive_failures: 0
ENDSTATE
    # Convert to persistent task
    $TASKCTL from-suggestion "$SUGGESTION_FILE" 2>/dev/null || true
    # Mark generator state
    GEN_COUNT=$(grep 'generation_count:' "$GEN_STATE_FILE" | awk '{print $2}')
    GEN_COUNT=${GEN_COUNT:-0}
    TITLE=$(grep '^title:' "$SUGGESTION_FILE" | sed 's/^title: *//' | sed 's/^"//;s/"$//')
    cat > "$GEN_STATE_FILE" << ENDSTATE
version: 1
capabilities:
  - identity-files (IDENTITY.md, USER.md, SOUL.md)
  - file-io
  - shell
  - idea-generator
  - idea-executor
  - tasks
  - web-search
  - python
last_suggestion_topic: ${TITLE:-unknown}
last_suggestion_accepted: true
generation_count: $GEN_COUNT
ENDSTATE
  else
    # Task from task list — mark done
    $TASKCTL done "$NEXT_TASK" 2>/dev/null || true
  fi
else
  log "❌ Implementation failed (exit $EXIT_CODE)"
  CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
  FAILURE_COUNT=$((FAILURE_COUNT + 1))
  
  if [ "$NEXT_TASK" = "suggestion-"* ]; then
    cat > "$STATE_FILE" << ENDSTATE
last_processed_id: "$SUGGESTION_ID"
last_result: failure
failure_count: "$FAILURE_COUNT"
consecutive_failures: "$CONSECUTIVE_FAILS"
ENDSTATE
  else
    $TASKCTL note "$NEXT_TASK" "Failed implementation (exit $EXIT_CODE)" 2>/dev/null || true
  fi
fi

log "done"
