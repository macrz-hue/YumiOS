<#
.YumiOS Windows Deployer — PowerShell script
Run this in PowerShell as Administrator:

  irm https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup-windows.ps1 | iex

This will install everything needed to run YumiOS locally.
#>

$ErrorActionPreference = "Stop"
$YumiOSDir = "$env:USERPROFILE\YumiOS"
$WslDir = "/root/.openclaw/workspace"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      YumiOS — Windows Deployer               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "❌ Please run PowerShell as Administrator" -ForegroundColor Red
    exit 1
}

# 2. Install/check WSL2
Write-Host "📦 Step 1: Checking WSL2..." -ForegroundColor Yellow
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host "  Installing WSL2 (this may take a few minutes)..." -ForegroundColor Gray
    wsl --install -d Ubuntu
    Write-Host "  ✅ WSL2 + Ubuntu installed. You may need to reboot."
    Write-Host "  After reboot, run this script again."
    exit 0
} else {
    Write-Host "  ✅ WSL2 is available" -ForegroundColor Green
}

# 3. Check for Ubuntu distro
$distros = wsl -l -q 2>$null
if ($distros -notmatch "Ubuntu") {
    Write-Host "  Installing Ubuntu WSL distro..." -ForegroundColor Gray
    wsl --install -d Ubuntu
}
Write-Host "  ✅ Ubuntu WSL distro ready" -ForegroundColor Green

# 4. Clone repo
Write-Host "📦 Step 2: Cloning YumiOS..." -ForegroundColor Yellow
wsl bash -c "if [ ! -d '$WslDir' ]; then mkdir -p '$WslDir' && git clone https://github.com/macrz-hue/YumiOS.git '$WslDir' 2>/dev/null || true; fi"
wsl bash -c "cd '$WslDir' && git pull 2>/dev/null || true"
Write-Host "  ✅ YumiOS cloned" -ForegroundColor Green

# 5. Run bootstrap inside WSL
Write-Host "📦 Step 3: Running bootstrap installer..." -ForegroundColor Yellow
Write-Host "  This installs Python, builds llama-server, downloads the model (~2 GB)."
Write-Host "  It will take 5-15 minutes depending on your machine." -ForegroundColor Gray

wsl bash -c "cd '$WslDir' && bash scripts/setup.sh 2>&1" | ForEach-Object { Write-Host "  $_" }

Write-Host "  ✅ Bootstrap complete" -ForegroundColor Green

# 6. Install yumehiru CLI commands
Write-Host "📦 Step 4: Installing CLI shortcuts..." -ForegroundColor Yellow
$wslIp = wsl hostname -I 2>$null | ForEach-Object { $_.Trim() }
$wslIp = ($wslIp -split ' ')[0]

# Create batch file for easy access
@"
@echo off
wsl bash -c "cd ~/.openclaw/workspace && scripts\%*"
"@ | Out-File -FilePath "$env:SystemRoot\yumehiru.cmd" -Encoding ASCII -Force

Write-Host "  ✅ CLI installed — use 'yumehiru' from any terminal" -ForegroundColor Green

# 7. Show completion
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      ✅ YumiOS is ready!                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  📊 Dashboard:   http://localhost:18082" -ForegroundColor White
Write-Host "  🎤 Voice CLI:   yumehiru" -ForegroundColor White
Write-Host "  🔑 Set password:" -ForegroundColor White
Write-Host "     wsl bash -c 'cd ~/.openclaw/workspace && python3 scripts/yumehiru-passwd.py passwd \"your-password\"'"
Write-Host ""
Write-Host "  📋 Commands:" -ForegroundColor Gray
Write-Host "     yumehiru status       — System health" -ForegroundColor Gray
Write-Host "     yumehiru tasks        — List tasks" -ForegroundColor Gray
Write-Host "     yumehiru alerts       — Current alerts" -ForegroundColor Gray
Write-Host "     yumehiru speak        — Speak status aloud" -ForegroundColor Gray
Write-Host "     yumehiru-llm 'ask'    — Ask the local LLM" -ForegroundColor Gray
Write-Host ""
Write-Host "  Open http://localhost:18082 in your browser!" -ForegroundColor Cyan
