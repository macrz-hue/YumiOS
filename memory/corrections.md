## Correction #1 (2026-07-04)
- **Trigger:** Told user the URL instead of opening browser
- **Correction:** When user asks to see UI, I must open browser myself and navigate there — never just give them the URL
- **Applied:** Sat Jul  4 20:13:26 UTC 2026

## Correction #2 (2026-07-04)
- **Trigger:** No firewall rules — all ports open
- **Correction:** Applied iptables: only ports 22, 80, 443, 18082 are open. Yumehiru dashboard is the only service exposed externally.
- **Applied:** Sat Jul  4 20:33:26 UTC 2026

## Correction #3 (2026-07-04)
- **Trigger:** No brute force protection
- **Correction:** Installed and enabled fail2ban for SSH brute force prevention.
- **Applied:** Sat Jul  4 20:33:26 UTC 2026

