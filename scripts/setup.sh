#!/bin/bash
# Yumehiru Bootstrap Installer — setup a fresh system in one command
# Usage: curl -sL https://raw.githubusercontent.com/.../setup.sh | bash
# Or: bash setup.sh [--dev] [--model <url>]
set -euo pipefail

# Config
WORKSPACE="${WORKSPACE:-/root/.openclaw/workspace}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf}"
MODEL_FILE="/root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf"
LLAMA_VERSION="b9871"
GITHUB_REPO=""  # Set this when published
DEV_MODE=false

# Parse args
for arg in "$@"; do
  [ "$arg" = "--dev" ] && DEV_MODE=true
done

echo "╔══════════════════════════════════════════════╗"
echo "║    Yumehiru — Bootstrap Installer            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Must run as root"
  exit 1
fi

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "📍 OS: $OS $ARCH"

if [ "$OS" != "Linux" ] || [ "$ARCH" != "x86_64" ]; then
  echo "⚠️  Only Linux x86_64 is fully tested. Proceeding anyway..."
fi

# --------------------------------------------------
# Step 1: System dependencies
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 1/8: System dependencies"
echo "────────────────────────────────────────────"

apt-get update -qq
apt-get install -y -qq \
  curl wget git cmake build-essential \
  python3 python3-pip python3-venv \
  pkg-config libssl-dev \
  systemd

echo "  ✅ System packages installed"

# --------------------------------------------------
# Step 2: Python environment
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 2/8: Python virtual environment"
echo "────────────────────────────────────────────"

VENV="$WORKSPACE/.venv"
python3 -m venv "$VENV"
source "$VENV/bin/activate"
pip install -q ddgs wikipedia-api beautifulsoup4 requests
echo "  ✅ Python venv with $(pip list 2>/dev/null | wc -l) packages"

# --------------------------------------------------
# Step 3: Workspace structure
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 3/8: Workspace structure"
echo "────────────────────────────────────────────"

# Clone if repo URL provided, otherwise create structure
if [ -n "$GITHUB_REPO" ] && [ ! -d "$WORKSPACE/.git" ]; then
  git clone "$GITHUB_REPO" "$WORKSPACE" 2>/dev/null || echo "  ⚠️  Clone failed, using local files"
fi

mkdir -p "$WORKSPACE"/{agents/{idea-generator/{state,history},idea-executor/{state,logs},tools},tasks/{active,pending,blocked,done,archive},scripts,memory}

# Initialize task file
[ ! -f "$WORKSPACE/tasks/tasks.yaml" ] && echo "[]" > "$WORKSPACE/tasks/tasks.yaml"

# Create .gitignore
cat > "$WORKSPACE/.gitignore" << 'GITIGNORE'
.venv/
__pycache__/
*.pyc
node_modules/
.trash/
*.gguf
GITIGNORE

echo "  ✅ Workspace structure created"

# --------------------------------------------------
# Step 4: Send shell scripts and agent files
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 4/8: Agent and tool scripts"
echo "────────────────────────────────────────────"

# Note: In a real deploy, these come from git.
# For local bootstrap, they should already exist.
if [ ! -f "$WORKSPACE/scripts/taskctl.sh" ]; then
  echo "  ⚠️  Agent scripts not found — workspace may be incomplete."
  echo "     Clone the repo or copy files manually."
else
  chmod +x "$WORKSPACE"/scripts/*.sh 2>/dev/null || true
  chmod +x "$WORKSPACE"/agents/*/*.sh 2>/dev/null || true
  chmod +x "$WORKSPACE"/agents/tools/*.sh 2>/dev/null || true
  echo "  ✅ Agent scripts ready"
fi

# --------------------------------------------------
# Step 5: llama-server binary
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 5/8: llama-server binary"
echo "────────────────────────────────────────────"

LLAMA_BIN="/usr/local/bin/llama-server"
if [ -f "$LLAMA_BIN" ] && [ -x "$LLAMA_BIN" ]; then
  echo "  ✅ llama-server already installed"
else
  echo "  ⏳ Downloading llama-server (this may take a minute)..."
  
  # Try pre-built binary first
  BINARY_URL="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_VERSION/llama-$LLAMA_VERSION-bin-ubuntu-x64.tar.gz"
  TMP_DIR=$(mktemp -d)
  
  if curl -sL "$BINARY_URL" -o "$TMP_DIR/llama.tar.gz" && tar xzf "$TMP_DIR/llama.tar.gz" -C "$TMP_DIR" 2>/dev/null; then
    find "$TMP_DIR" -name "llama-server" -type f -exec cp {} "$LLAMA_BIN" \; 2>/dev/null || true
    chmod +x "$LLAMA_BIN" 2>/dev/null || true
  fi
  
  # If binary download failed, build from source
  if [ ! -f "$LLAMA_BIN" ] || [ ! -x "$LLAMA_BIN" ]; then
    echo "  ⏳ Pre-built binary not found, building from source..."
    git clone --depth 1 --branch "b$LLAMA_VERSION" https://github.com/ggml-org/llama.cpp "$TMP_DIR/source" 2>/dev/null || true
    if [ -d "$TMP_DIR/source" ]; then
      mkdir -p "$TMP_DIR/build"
      cd "$TMP_DIR/build"
      cmake "$TMP_DIR/source" -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_EXAMPLES=ON -DGGML_CUDA=OFF -DCMAKE_BUILD_TYPE=Release 2>/dev/null
      make -j$(nproc) llama-server 2>/dev/null && cp bin/llama-server "$LLAMA_BIN" 2>/dev/null || true
    fi
  fi
  
  rm -rf "$TMP_DIR"
  
  if [ -f "$LLAMA_BIN" ] && [ -x "$LLAMA_BIN" ]; then
    echo "  ✅ llama-server built and installed"
  else
    echo "  ⚠️  Could not build llama-server. Install manually."
  fi
fi

# --------------------------------------------------
# Step 6: LLM model
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 6/8: LLM model download (~2 GB)"
echo "────────────────────────────────────────────"

mkdir -p "$(dirname "$MODEL_FILE")"
if [ -f "$MODEL_FILE" ]; then
  SIZE=$(stat -c%s "$MODEL_FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 1000000000 ]; then
    echo "  ✅ Model already downloaded ($(du -h "$MODEL_FILE" | cut -f1))"
  else
    echo "  ⚠️  Model file incomplete, re-downloading..."
    curl -L "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
  fi
else
  echo "  ⏳ Downloading Llama 3.2 3B Instruct model (~2 GB)..."
  curl -L "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
fi

if [ -f "$MODEL_FILE" ]; then
  echo "  ✅ Model ready ($(du -h "$MODEL_FILE" | cut -f1))"
else
  echo "  ⚠️  Model download incomplete. Run: curl -L \"$MODEL_URL\" -o \"$MODEL_FILE\""
fi

# --------------------------------------------------
# Step 7: Systemd services
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 7/8: Systemd services"
echo "────────────────────────────────────────────"

# llama-server service
cat > /etc/systemd/system/llama-server.service << 'SERVICE'
[Unit]
Description=llama.cpp server for Yumehiru local LLM
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/llama-server -m /root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf --host 127.0.0.1 --port 18080 -c 4096 --mlock -ngl 0 -t 4
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
SERVICE

# Tool server service
cat > /etc/systemd/system/yumehiru-tools.service << 'SERVICE'
[Unit]
Description=Yumehiru Tool Server (web search, python, fetch)
After=llama-server.service
Requires=llama-server.service

[Service]
Type=simple
User=root
ExecStart=/root/.openclaw/workspace/.venv/bin/python3 /root/.openclaw/workspace/agents/tools/tool-server.py 18081
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable llama-server yumehiru-tools
systemctl start llama-server yumehiru-tools 2>/dev/null || true

echo "  ✅ Systemd services configured and enabled"

# --------------------------------------------------
# Step 8: Cron jobs
# --------------------------------------------------
echo ""
echo "────────────────────────────────────────────"
echo "Step 8/8: Cron jobs"
echo "────────────────────────────────────────────"

# Add cron entries if not already present
(crontab -l 2>/dev/null | grep -q "idea-generator") || {
  (crontab -l 2>/dev/null; echo "# Yumehiru Idea Generator - self-improvement every 15 min"; \
   echo "*/15 * * * * $WORKSPACE/agents/idea-generator/generate.sh >> $WORKSPACE/agents/idea-generator/cron.log 2>&1"; \
   echo "# Yumehiru Idea Executor - implements tasks every 2 min"; \
   echo "*/2 * * * * $WORKSPACE/agents/idea-executor/execute.sh >> $WORKSPACE/agents/idea-executor/executor-cron.log 2>&1") | crontab -
  echo "  ✅ Cron jobs added"
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║    ✅ Bootstrap complete!                     ║"
echo "║                                              ║"
echo "║  Services:                                    ║"
echo "║    llama-server  → 127.0.0.1:18080           ║"
echo "║    tool-server   → 127.0.0.1:18081           ║"
echo "║                                              ║"
echo "║  Cron:                                        ║"
echo "║    Idea Generator  → every 15 min             ║"
echo "║    Idea Executor   → every 2 min              ║"
echo "║                                              ║"
echo "║  Check status:                                ║"
echo "║    systemctl status llama-server              ║"
echo "║    $WORKSPACE/scripts/taskctl.sh list      ║"
echo "╚══════════════════════════════════════════════╝"
