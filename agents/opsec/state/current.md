scan_count: 10
last_scan: 2026-07-04T20:33:18Z
overall_score: 85
findings:\n  - severity: medium\n    check: firewall_active\n    status: pass\n    detail: iptables active\n  - severity: medium\n    check: exposed_ports\n    status: pass\n    detail: Only dashboard (:18082) externally accessible\n  - severity: high\n    check: config_perms\n    status: pass\n    detail: Config 600\n  - severity: high\n    check: hardcoded_secrets\n    status: pass\n    detail: No hardcoded secrets in scripts\n  - severity: medium\n    check: outbound_ip\n    status: warn\n    detail: IP: 168.231.113.165 - no proxy/mask active\n  - severity: medium\n    check: fail2ban\n    status: pass\n    detail: fail2ban installed\n  - severity: medium\n    check: security_updates\n    status: pass\n    detail: No pending security updates
fixes_applied: 0
