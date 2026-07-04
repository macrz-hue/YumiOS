# YumiOS — Docker Quickstart

## Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- At least 8 GB RAM allocated to Docker
- ~4 GB free disk space

## One-command start

```powershell
# PowerShell (Admin)
irm https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup-windows.ps1 | iex
```

Or manually:

```bash
git clone https://github.com/macrz-hue/YumiOS.git
cd YumiOS
docker compose up -d
```

Then open **http://localhost:18082** in Chrome.

## Set admin password

```powershell
docker exec yumios yumehiru passwd "your-password"
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Dashboard | 18082 | Web UI (tasks, upload, alerts, LLM) |
| llama-server | 18080 | Local LLM inference |
| Tool server | 18081 | Web search, Python, URL fetch |

## Data persistence

```yaml
volumes:
  - yumios_data:/root/.openclaw/workspace  # Configs, tasks, corrections
  - yumios_models:/root/.node-llama-cpp/models  # LLM model
```

## Stop & restart

```bash
docker compose down     # Stop
docker compose up -d    # Start again
docker compose logs -f  # Watch logs
```
