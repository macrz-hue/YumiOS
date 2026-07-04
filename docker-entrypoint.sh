#!/bin/bash
# YumiOS Docker entrypoint
set -e

WORKSPACE="/root/.openclaw/workspace"
VENV="$WORKSPACE/.venv"
MODEL_DIR="/root/.node-llama-cpp/models"
MODEL_URL="https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
MODEL_FILE="$MODEL_DIR/llama-3.2-3b-instruct-q4_k_m.gguf"

echo "========================================"
echo "  YumiOS — Starting..."
echo "========================================"

# Activate venv
. "$VENV/bin/activate"

# Download model if missing
if [ ! -f "$MODEL_FILE" ]; then
    echo "[yumios] Downloading LLM model (~2 GB)..."
    mkdir -p "$MODEL_DIR"
    curl -L "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
fi

# Start llama-server
echo "[yumios] Starting llama-server..."
llama-server -m "$MODEL_FILE" --host 127.0.0.1 --port 18080 -c 4096 --mlock -ngl 0 -t 4 &
LLAMA_PID=$!

# Wait for llama-server
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:18080/health >/dev/null 2>&1; then
        echo "[yumios] llama-server ready"
        break
    fi
    sleep 2
done

# Start tool server
echo "[yumios] Starting tool server..."
python3 "$WORKSPACE/agents/tools/tool-server.py" 18081 &
TOOL_PID=$!

# Start dashboard
echo "[yumios] Starting dashboard..."
python3 "$WORKSPACE/agents/dashboard/server.py" 18082 &
DASH_PID=$!

echo "========================================"
echo "  YumiOS ready!"
echo "  Dashboard: http://localhost:18082"
echo "========================================"

# Trap shutdown
trap "kill $LLAMA_PID $TOOL_PID $DASH_PID 2>/dev/null; exit" SIGTERM SIGINT

# Keep running
wait
