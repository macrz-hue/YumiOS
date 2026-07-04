<#
.YumiOS — Docker Desktop Quickstart
Run this in PowerShell (Admin recommended):

  irm https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup-windows.ps1 | iex

Prerequisites: Docker Desktop installed and running.
#>

$ErrorActionPreference = "Continue"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      YumiOS — Docker Desktop Deployer       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""

# 1. Check Docker
Write-Host "📦 Step 1: Checking Docker Desktop..." -ForegroundColor Yellow
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host "❌ Docker not found. Install Docker Desktop from:" -ForegroundColor Red
    Write-Host "   https://www.docker.com/products/docker-desktop/"
    exit 1
}

$dockerVer = docker --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker is installed but not running." -ForegroundColor Yellow
    Write-Host "   Please start Docker Desktop and retry."
    exit 1
}
Write-Host "  ✅ $dockerVer" -ForegroundColor Green

# 2. Clone repo
Write-Host "📦 Step 2: Fetching YumiOS..." -ForegroundColor Yellow
if (Test-Path "YumiOS") {
    cd YumiOS
    git pull 2>$null
} else {
    git clone https://github.com/macrz-hue/YumiOS.git
    cd YumiOS
}
Write-Host "  ✅ YumiOS fetched" -ForegroundColor Green

# 3. Build and start
Write-Host "📦 Step 3: Building and starting containers..." -ForegroundColor Yellow
Write-Host "  First launch downloads the LLM model (~2 GB). This takes 5-15 min." -ForegroundColor Gray
docker compose up -d --build 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host "  ✅ Containers running" -ForegroundColor Green

# 4. Set password
Write-Host "📦 Step 4: Set your admin password..." -ForegroundColor Yellow
$pw = Read-Host "  Enter admin password (or press Enter to skip)"
if ($pw) {
    docker exec yumios bash -c "cd /root/.openclaw/workspace && python3 scripts/yumehiru-passwd.py passwd '$pw'" 2>&1 | ForEach-Object { Write-Host "  $_" }
}

# 5. Done
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      ✅ YumiOS is running!                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  📊 Dashboard:   http://localhost:18082"
Write-Host "  🔑 Password:    docker exec yumios yumehiru passwd"
Write-Host "  📋 Status:      docker exec yumios bash -c 'yumehiru status'"
Write-Host ""
Write-Host "  Useful commands:"
Write-Host "    docker compose logs -f     — Watch logs"
Write-Host "    docker compose down        — Stop YumiOS"
Write-Host "    docker compose up -d       — Start again"
Write-Host ""
Write-Host "  Open http://localhost:18082 in your browser!" -ForegroundColor Cyan
