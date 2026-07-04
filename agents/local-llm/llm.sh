#!/bin/bash
# Local LLM inference using llama-server
set -euo pipefail

HOST="127.0.0.1"
PORT="18080"
MODEL="/root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf"
SERVER_BIN="/usr/local/bin/llama-server"
PID_FILE="/tmp/llama-server.pid"

start_server() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        return 0
    fi
    nohup "$SERVER_BIN" -m "$MODEL" --host "$HOST" --port "$PORT" \
        -c 4096 --mlock --no-mmap \
        > /tmp/llama-server-stdout.log 2> /tmp/llama-server-stderr.log &
    echo $! > "$PID_FILE"
    # Wait for it to be ready
    for i in $(seq 1 30); do
        if curl -s "http://$HOST:$PORT/health" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

case "${1:-}" in
    start)
        start_server
        echo "Server started (PID: $(cat "$PID_FILE"))"
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "Server stopped"
        fi
        ;;
    generate)
        shift
        PROMPT="${1:-}"
        if [ -z "$PROMPT" ]; then
            echo "Usage: llm.sh generate <prompt>"
            exit 1
        fi
        start_server
        curl -s "http://$HOST:$PORT/completion" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\": \"$(echo "$PROMPT" | sed 's/"/\\"/g')\", \"n_predict\": 512, \"temperature\": 0.7}" \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('content',''))" 2>/dev/null
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Server running (PID: $(cat "$PID_FILE"))"
        else
            echo "Server not running"
        fi
        ;;
    *)
        echo "Usage: llm.sh {start|stop|generate|status}"
        ;;
esac
