#!/bin/bash
# Yumehiru Tool Runner — wraps the tool server for sub-agent scripts
# Usage: tools.sh web_search <query>
#        tools.sh run_python '<code>'
#        tools.sh wikipedia <topic>
#        tools.sh fetch <url>
set -euo pipefail

TOOL_URL="http://127.0.0.1:18081"
CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
  web_search)
    curl -s "$TOOL_URL/web_search" -H "Content-Type: application/json" \
      -d "{\"query\": $(echo "$*" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}"
    ;;
  run_python)
    curl -s "$TOOL_URL/run_python" -H "Content-Type: application/json" \
      -d "{\"code\": $(echo "$*" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}"
    ;;
  wikipedia)
    curl -s "$TOOL_URL/wikipedia" -H "Content-Type: application/json" \
      -d "{\"title\": $(echo "$*" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}"
    ;;
  fetch)
    curl -s "$TOOL_URL/fetch" -H "Content-Type: application/json" \
      -d "{\"url\": $(echo "$*" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")}"
    ;;
  health)
    curl -s "$TOOL_URL/health"
    ;;
  *)
    echo "Usage: tools.sh {web_search|run_python|wikipedia|fetch|health} [args]"
    exit 1
    ;;
esac
echo
