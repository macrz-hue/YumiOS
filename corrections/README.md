# Corrections Log — Yumehiru's Learning System

Every time I get corrected, this file records:
- What I did wrong
- What I should have done instead
- Whether it's been applied as a default behavior

On startup and periodically, I read this file and update my behavior accordingly.

## How to Add a Correction
```bash
corrections log "what I did wrong" "what I should do instead" [--apply]
```

## Format
Each correction becomes an entry in `corrections/corrections.yaml`:
```yaml
- id: 1
  timestamp: "2026-07-04T20:12:00Z"
  trigger: "what I did wrong / what I was told"
  correction: "what I should do instead by default"
  applied: false
```

When `applied: true`, the correction is read at startup and wired into AGENTS.md or the relevant config.
