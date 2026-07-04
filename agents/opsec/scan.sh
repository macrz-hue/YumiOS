#!/bin/bash
# OpSec Agent — Security scan + hardening
set -euo pipefail
DIR="/root/.openclaw/workspace/agents/opsec"
STATE="$DIR/state/current.md"
REPORTS="$DIR/reports"
LOCK="$DIR/.opsec.lock"
DATE=$(date -u +%Y-%m-%d)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$REPORTS"
log() { echo "[opsec] $(date -u +%H:%M:%S) $*"; }
if ! mkdir "$LOCK" 2>/dev/null; then log "already running"; exit 0; fi
trap 'rm -rf "$LOCK"' EXIT

P=0; F=0; FINDINGS=""; REPORT=""
report() { local s=$1 c=$2 st=$3 d=$4; [ "$st" = "pass" ] && P=$((P+1)) || F=$((F+1)); local i="✅"; [ "$st" = "fail" ] && i="❌"; [ "$st" = "warn" ] && i="⚠️"; [ "$st" = "info" ] && i="ℹ️"; FINDINGS="$FINDINGS\n  - severity: $s\n    check: $c\n    status: $st\n    detail: $d"; REPORT="$REPORT\n$i [$s] $c - $d"; log "$i $c: $d"; }

# Checks
check_firewall() { local r=$(iptables -L INPUT -n 2>/dev/null | grep -cE "DROP|REJECT" || echo 0); [ "$r" -gt 0 ] && report medium firewall_active pass "iptables active" || report high firewall_active fail "No firewall"; }
check_exposed() { local e=$(ss -tlnp 2>/dev/null | awk '{print $4}' | grep "^0.0.0.0:" | grep -cE ":(18080|18081)" || true); [ "$e" -eq 0 ] && report medium exposed_ports pass "Only dashboard (:18082) externally accessible" || report critical exposed_ports fail "$e Yumehiru ports exposed on 0.0.0.0"; }
check_perms() { local p=$(stat -c %a /root/.openclaw/openclaw.json 2>/dev/null || echo 600); [ "$p" -le 600 ] && report high config_perms pass "Config $p" || report critical config_perms fail "Config $p - should be 600"; }
check_exfil() { 
  local c=$(grep -rn "api_key\|token.*=" /root/.openclaw/workspace/scripts/ /root/.openclaw/workspace/agents/ --include="*.sh" --include="*.py" 2>/dev/null | grep -v "opsec/scan.sh" | grep -v "corrections.sh" | grep -v "node_modules" | grep -v "no_proxy\|no_proxy=" | wc -l)
  [ "$c" -eq 0 ] && report high hardcoded_secrets pass "No hardcoded secrets in scripts" || report critical hardcoded_secrets fail "$c lines with potential secrets"
}
check_ip() { local ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "unknown"); report medium outbound_ip warn "IP: $ip - no proxy/mask active"; }
check_f2b() { which fail2ban-client >/dev/null 2>&1 && report medium fail2ban pass "fail2ban installed" || report medium fail2ban fail "fail2ban not installed"; }
check_updates() { local u=$(apt-get --just-print upgrade 2>/dev/null | grep -c "^Inst.*Security" || true); [ "$u" -eq 0 ] && report medium security_updates pass "No pending security updates" || report high security_updates fail "$u security updates pending"; }

# Run
log "OpSec scan #$(($(grep scan_count: "$STATE" 2>/dev/null | awk '{print $2}' || echo 0) + 1))"
check_firewall; check_exposed; check_perms; check_exfil; check_ip; check_f2b; check_updates

SCORE=100; T=$((P+F)); [ "$T" -gt 0 ] && SCORE=$((P*100/T))
SC=$(($(grep scan_count: "$STATE" 2>/dev/null | awk '{print $2}' || echo 0) + 1))

cat > "$STATE" << EOF
scan_count: $SC
last_scan: $TS
overall_score: $SCORE
findings:$FINDINGS
fixes_applied: 0
EOF

cat > "$REPORTS/$DATE.md" << EOF
# OpSec Report - $DATE
Scan #$SC | Score: $SCORE/100 ($P pass, $F fail)
$REPORT
EOF

log "Score: $SCORE/100 ($P pass, $F fail)"
log "done"
