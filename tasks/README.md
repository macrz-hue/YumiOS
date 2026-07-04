# Task Tracking System — Yumehiru

Persistent task management so Yumehiru picks up where it left off, every session.

## Task Lifecycle

```
pending → active → done
              ↓
          blocked
```

## File Format (`tasks/tasks.yaml`)

```yaml
- id: 1
  title: "Short title"
  status: pending|active|blocked|done
  priority: high|medium|low
  created: "2026-07-04T19:20:00Z"
  updated: "2026-07-04T19:30:00Z"
  source: "idea-generator #1"
  tags: [infrastructure, automation]
  notes: "Implementation details or context"
```

## How It Works

- **Generator** creates ideas → accepted ones become tasks
- **Executor** picks highest priority pending task → moves to active → works → moves to done/blocked
- **On startup**, Yumehiru checks `tasks/tasks.yaml` for active/pending tasks and resumes
- **Done tasks** move to `archive/` directory

## Directories

| Path | Purpose |
|------|---------|
| `tasks/tasks.yaml` | Master task manifest |
| `tasks/archive/` | Completed task files (moved after done) |
| `active/`, `pending/`, `blocked/` | Status-based subdirs (optional) |
