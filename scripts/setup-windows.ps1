<#
.YumiOS Windows Deployer — PowerShell script
Run in PowerShell as Administrator:

  irm https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup-windows.ps1 | iex

Prerequisites: Windows 10/11 with WSL2 installed.
#>

$ErrorActionPreference = "Continue"
$YumiOSDir = "$env:USERPROFILE\YumiOS"
$WslDir = "/root/.openclaw/workspace"

function wsl-run {
    param([string]$cmd)
    wsl -e bash -c $cmd 2>&1 | Out-Host
    return $LASTEXITCODE
}

function wsl-cmd {
    param([string]$cmd)
    return wsl -e bash -c $cmd 2>&1
}

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      YumiOS — Windows Deployer               ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""

# 1. Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "❌ Please run PowerShell as Administrator" -ForegroundColor Red
    exit 1
}

# 2. Check WSL
Write-Host "📦 Step 1: Checking WSL2..." -ForegroundColor Yellow
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host "  Installing WSL2 (reboot may be required)..." -ForegroundColor Gray
    wsl --install -d Ubuntu
    Write-Host "  ✅ WSL2 installed. If prompted, reboot and re-run this script."
    exit 0
}
Write-Host "  ✅ WSL2 available" -ForegroundColor Green

# 3. Ensure Ubuntu distro
$distros = wsl -l -q 2>$null
if ($distros -notmatch "Ubuntu") {
    Write-Host "  Installing Ubuntu..." -ForegroundColor Gray
    wsl --install -d Ubuntu
}
Write-Host "  ✅ Ubuntu distro ready" -ForegroundColor Green

# 4. Check bash works in WSL
Write-Host "📦 Step 2: Testing WSL shell..." -ForegroundColor Yellow
$testBash = wsl -e bash -c "echo bash_ok" 2>$null
if ($testBash -ne "bash_ok") {
    Write-Host "  ⚠️ Bash not found in default WSL path. Installing bash..." -ForegroundColor Yellow
    wsl apt-get update -qq 2>$null
    wsl apt-get install -y -qq bash 2>$null
    $testBash = wsl -e bash -c "echo bash_ok" 2>$null
    if ($testBash -ne "bash_ok") {
        Write-Host "  ❌ Could not get bash working in WSL." -ForegroundColor Red
        Write-Host "  Please run: wsl --install -d Ubuntu (from cmd), then retry."
        exit 1
    }
}
Write-Host "  ✅ WSL shell ready" -ForegroundColor Green

# 5. Clone/update repo
Write-Host "📦 Step 3: Cloning YumiOS..." -ForegroundColor Yellow
wsl-run "mkdir -p $WslDir"
wsl-run "cd $WslDir && if [ ! -d .git ]; then git clone https://github.com/macrz-hue/YumiOS.git . 2>/dev/null; else git pull 2>/dev/null; fi"
Write-Host "  ✅ YumiOS cloned to WSL" -ForegroundColor Green

# 6. Run bootstrap
Write-Host "📦 Step 4: Running bootstrap (this takes 5-15 min)..." -ForegroundColor Yellow
Write-Host "  Installing Python, building LLM, downloading model (~2 GB)" -ForegroundColor Gray
wsl-run "cd $WslDir && bash scripts/setup.sh"
Write-Host "  ✅ Bootstrap complete" -ForegroundColor Green

# 7. Set default command
Write-Host "📦 Step 5: Installing yumehiru CLI..." -ForegroundColor Yellow
$wslIp = wsl -e bash -c "hostname -I 2>/dev/null || ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1 || echo 'localhost'" 2>$null
$wslIp = ($wslIp -split ' ')[0].Trim()

@"
@echo off
wsl -e bash -c "cd $WslDir && scripts\%*"
"@ | Out-File -FilePath "$env:SYSTEMROOT\yumehiru.cmd" -Encoding ASCII -Force 2>$null

Write-Host "  ✅ Type 'yumehiru' in any terminal" -ForegroundColor Green

# 8. Done
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      ✅ YumiOS is ready!                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "  📊 Dashboard:   http://localhost:18082"
Write-Host "  🔑 Set password:"
Write-Host "     wsl -e bash -c 'cd $WslDir && python3 scripts/yumehiru-passwd.py passwd \"your-password\"'"
Write-Host ""
Write-Host "  📋 yumehiru status       — System health"
Write-Host "     yumehiru tasks        — List tasks"
Write-Host "     yumehiru alerts       — Current alerts"
Write-Host "     yumehiru speak        — Speak status aloud"
Write-Host "     yumehiru-llm 'ask'    — Ask the local LLM"
Write-Host ""
Write-Host "  Open http://localhost:18082 in your browser!" -ForegroundColor Cyan
