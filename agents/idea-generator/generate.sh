#!/bin/bash
# Idea Generator — Self-Improvement Loop
# Uses local LLM + tools (web search, python, fetch) for research-backed ideas.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="$DIR/state/current.md"
SUGGESTION_FILE="$DIR/state/latest-suggestion.md"
HISTORY_DIR="$DIR/history"
LOCK_FILE="$DIR/.generator.lock"
LLM_CMD="/usr/local/bin/yumehiru-llm"
TOOL_URL="http://127.0.0.1:18081"

log() { echo "[idea-generator] $(date -u +%H:%M:%S) $*"; }
if ! mkdir "$LOCK_FILE" 2>/dev/null; then log "already running"; exit 0; fi
trap 'rm -rf "$LOCK_FILE"' EXIT

# Read state
CURRENT_TOPIC=$(grep 'last_suggestion_topic:' "$STATE_FILE" | awk '{print $2}')
CURRENT_COUNT=$(grep 'generation_count:' "$STATE_FILE" | awk '{print $2}')
CURRENT_COUNT=${CURRENT_COUNT:-0}
NEW_COUNT=$((CURRENT_COUNT + 1))
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log "generating suggestion #$NEW_COUNT (last: ${CURRENT_TOPIC:-none})"

# Check servers
for url in "$LLM_URL" "$TOOL_URL/health"; do
  base=$(echo "$url" | cut -d/ -f1-3)
  if ! curl -sf "$base/health" >/dev/null 2>&1; then
    log "ERROR: $base not responding"
    exit 1
  fi
done

# Build prompts
SYSTEM_PROMPT=$(cat << ENDPROMPT
You are the Idea Generator — a self-improvement meta-agent.

Current build:
- Version: 1
- Capabilities: identity-files, file-io, shell, idea-generator, idea-executor, web-search, python, fetch-url
- Suggestions so far: $CURRENT_COUNT
- Last topic: ${CURRENT_TOPIC:-none}

Generate ONE concrete, actionable upgrade prompt. Do NOT repeat: ${CURRENT_TOPIC:-none}. Prefer incremental improvements.

You can use tools to research before generating:
- TOOL: web_search | <query> — search the web
- TOOL: run_python | <python code> — execute python
- TOOL: fetch_url | <url> — fetch a web page

If you use a tool, I'll run it and give you the result. Then continue with your YAML.
ENDPROMPT
)

USER_PROMPT=$(cat << ENDPROMPT
Output ONLY valid YAML:
suggestion_id: $NEW_COUNT
generated_at: "$TIMESTAMP"
target: <file, capability, or workflow>
title: <short one-liner>
prompt: <2-4 sentence actionable upgrade>
reasoning: <1 sentence why>

No preamble, no explanation. Only the YAML block.
ENDPROMPT
)

# Call LLM with tool loop
MESSAGES=$(python3 << PYEOF
import json
msgs = [
    {"role": "system", "content": $(echo "$SYSTEM_PROMPT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")},
    {"role": "user", "content": $(echo "$USER_PROMPT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")}
]
print(json.dumps(msgs))
PYEOF
)

MAX_ROUNDS=3
for ((round=0; round<MAX_ROUNDS; round++)); do
  # Call LLM
  RAW=$($LLM_CMD --json '{"messages":
    -d "$(python3 << PYEOF
import json
msgs = json.loads($(echo "$MESSAGES" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"))
print(json.dumps({"messages": msgs, "max_tokens": 1024, "temperature": 0.7}))
PYEOF
)" 2>/dev/null)

  RESPONSE=$(echo "$RAW" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)['choices'][0]['message']['content'])
except: print('PARSE_ERROR')
" 2>/dev/null)

  if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "PARSE_ERROR" ]; then
    log "ERROR: bad response from LLM"
    exit 1
  fi

  # Check for tool call
  TOOL_LINE=$(echo "$RESPONSE" | grep '^TOOL:' | head -1)
  [ -z "$TOOL_LINE" ] && break

  log "tool: $TOOL_LINE"
  TOOL_NAME=$(echo "$TOOL_LINE" | sed 's/^TOOL: *//' | cut -d'|' -f1 | xargs)
  TOOL_ARGS=$(echo "$TOOL_LINE" | sed 's/^TOOL: *//' | cut -d'|' -f2- | xargs)

  TOOL_RESULT=""
  case "$TOOL_NAME" in
    web_search)
      TOOL_RESULT=$(curl -s "$TOOL_URL/web_search" -H "Content-Type: application/json" \
        -d "$(python3 -c "import json; print(json.dumps({'query': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))"), 'max': 5}))")")
      ;;
    run_python)
      TOOL_RESULT=$(curl -s "$TOOL_URL/run_python" -H "Content-Type: application/json" \
        -d "$(python3 -c "import json; print(json.dumps({'code': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}))")")
      ;;
    fetch_url)
      TOOL_RESULT=$(curl -s "$TOOL_URL/fetch" -H "Content-Type: application/json" \
        -d "$(python3 -c "import json; print(json.dumps({'url': $(echo "$TOOL_ARGS" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}))")")
      ;;
  esac

  [ -z "$TOOL_RESULT" ] && TOOL_RESULT='{"error":"empty result"}'

  # Append assistant response + tool result to messages
  MESSAGES=$(python3 << PYEOF
import json
msgs = json.loads($(echo "$MESSAGES" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"))
msgs.append({"role": "assistant", "content": $(echo "$RESPONSE" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")})
msgs.append({"role": "tool", "content": $(echo "$TOOL_RESULT" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))")})
print(json.dumps(msgs))
PYEOF
)
done

# Extract YAML from final response
YAML=$(echo "$RESPONSE" | sed -n '/^suggestion_id:/,/^reasoning:/p')
[ -z "$YAML" ] && YAML=$(echo "$RESPONSE" | sed -n '/```[yY][aA][mM][lL]*/,/```/{//d;p}')
[ -z "$YAML" ] && YAML=$(echo "$RESPONSE" | sed -n '/```/,/```/{//d;p}')

if [ -z "$YAML" ]; then
  log "WARNING: no YAML, saving raw"
  echo "# Raw at $TIMESTAMP" > "$SUGGESTION_FILE"
  echo "$RESPONSE" >> "$SUGGESTION_FILE"
  exit 0
fi

# Save
echo "$YAML" > "$SUGGESTION_FILE"
cp "$SUGGESTION_FILE" "$HISTORY_DIR/${TIMESTAMP}.md"

# Update state
TITLE=$(echo "$YAML" | grep '^title:' | sed 's/^title: *//' | sed 's/^"//;s/"$//')
cat > "$STATE_FILE" << ENDSTATE
version: 1
capabilities:
  - identity-files (IDENTITY.md, USER.md, SOUL.md)
  - file-io
  - shell
  - idea-generator
  - idea-executor
last_suggestion_topic: ${TITLE:-unknown}
last_suggestion_accepted: null
generation_count: $NEW_COUNT
ENDSTATE

log "✅ #$NEW_COUNT: ${TITLE:-(no title)}"
