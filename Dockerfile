FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WORKSPACE=/root/.openclaw/workspace

# System deps
RUN apt-get update -qq && apt-get install -y -qq \
    curl wget git cmake build-essential \
    python3 python3-pip python3-venv \
    espeak-ng tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace
COPY . "$WORKSPACE"

# Python venv
RUN python3 -m venv "$WORKSPACE/.venv" && \
    . "$WORKSPACE/.venv/bin/activate" && \
    pip install -q ddgs wikipedia-api beautifulsoup4 requests Pillow pytesseract

# Setup scripts
RUN chmod +x "$WORKSPACE"/scripts/*.sh "$WORKSPACE"/scripts/*.py "$WORKSPACE"/agents/**/*.sh 2>/dev/null || true
RUN ln -sf "$WORKSPACE/scripts/yumehiru-passwd.py" /usr/local/bin/yumehiru 2>/dev/null || true

# Entrypoint
COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 18080 18081 18082

VOLUME ["$WORKSPACE", "/root/.node-llama-cpp/models"]

ENTRYPOINT ["/entrypoint.sh"]
