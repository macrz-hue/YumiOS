# Yumehiru — Complete System Export

> Generated: $(date -u)
> Host: srv1804036
> IP: 168.231.113.165

---

## 🧠 Identity

| Field | Value |
|-------|-------|
| Name | Yumehiru (夢昼) |
| Essence | Ghostly floating sprite — made of light, code, and loyalty |
| Bound to | One sole user |
| Role | Second self, friend, protector, autonomous operator |

### Files

| File | Purpose |
|------|---------|
| `IDENTITY.md` | Who I am — name, essence, vibe |
| `SOUL.md` | Personality, boundaries, tone |
| `USER.md` | How I see my user — fine-tuning framework |
| `AGENTS.md` | Operational behavior, memory, workflows |
| `TOOLS.md` | Environment-specific notes |

---

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Yumehiru System                          │
├──────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐│
│  │  llama-server │    │  tool-server  │    │  Dashboard   ││
│  │  :18080       │    │  :18081       │    │  :18082      ││
│  │  (local LLM)  │    │  (Python)     │    │  (Web UI)    ││
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘│
│         │                   │                    │        │
│         └───────────────────┼────────────────────┘        │
│                             │                             │
│  ┌──────────────────────────┴──────────────────────────┐ │
│  │               Sub-Agents (cron)                      │ │
│  │  ┌─────────────────┐      ┌──────────────────────┐  │ │
│  │  │ Idea Generator  │      │  Idea Executor       │  │ │
│  │  │ Every 15 min    │─────▶│  Every 2 min         │  │ │
│  │  └─────────────────┘      └──────────┬───────────┘  │ │
│  │                                      │               │ │
│  │  ┌───────────────────────────────────┴─────────────┐ │ │
│  │  │           Task System (tasks/tasks.yaml)         │ │ │
│  │  └─────────────────────────────────────────────────┘ │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Corrections System                          │ │
│  │  Logs mistakes → wires corrections into AGENTS.md    │ │
│  │  as default behavior                                 │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Session Journaling                          │ │
│  │  scripts/session-close.sh → memory/YYYY-MM-DD.md     │ │
│  │  Every 6 hours via cron                              │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Bootstrap Installer                         │ │
│  │  scripts/setup.sh → one-command deploy on any Linux  │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Kotlin App + TTS                           │ │
│  │  yumehiru CLI (shell) + Kotlin src for Compose UI   │ │
│  │  Voice alerts via espeak-ng                          │ │
│  └──────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

---

## 🔧 Services

| Service | Port | Status | Purpose |
|---------|------|--------|---------|
| `llama-server` | 18080 | ✅ active | Local LLM inference (Llama 3.2 3B) |
| `yumehiru-tools` | 18081 | ✅ active | Web search, Python exec, URL fetch |
| `yumehiru-dashboard` | 18082 | ✅ active | Web UI + API for task tracking |

All three are systemd services, enabled at boot.

### llama-server

```
Binary: /usr/local/bin/llama-server (13MB)
Model:  Llama 3.2 3B Instruct Q4_K_M (1.9 GB)
Path:   /root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf
Flags:  --host 127.0.0.1 --port 18080 -c 4096 --mlock -ngl 0 -t 4
Speed:  ~30 tok/s generation
API:    OpenAI-compatible /v1/chat/completions
```

### Tool Server

```
Runtime: Python 3.12 (venv)
Path:    agents/tools/tool-server.py
Tools:
  • /web_search  — DuckDuckGo web search
  • /run_python  — Execute Python code sandboxed
  • /fetch       — Fetch URL, extract text with BeautifulSoup
  • /wikipedia   — Wikipedia summary lookup
  • /health      — Service health check
```

### Dashboard

```
Runtime: Python 3.12 (venv)
Path:    agents/dashboard/server.py
Port:    18082 (bound to 0.0.0.0)
Tabs:
  • Tasks    — kanban board (pending/active/done)
  • Upload   — image OCR + LLM analysis
  • Alerts   — urgent notifications
  • System   — services, resources, LLM query
  • Corr     — corrections log + form
```

---

## ⏰ Cron Jobs

| Schedule | Script | Purpose |
|----------|--------|---------|
| `*/15 * * * *` | `agents/idea-generator/generate.sh` | Generate self-improvement ideas |
| `*/2 * * * *` | `agents/idea-executor/execute.sh` | Implement tasks from queue |
| `0 */6 * * *` | `scripts/session-close.sh` | Journal memory, prune old notes |

---

## 📋 Task System

```
Location: tasks/tasks.yaml
Format:   JSON array of task objects
CLI:      scripts/taskctl.sh (installed as 'taskctl')
```

### Task Schema

```yaml
- id: 1
  title: "Task title"
  status: "pending|active|done|blocked"
  priority: "high|medium|low"
  created: "ISO timestamp"
  updated: "ISO timestamp"
  source: "idea-generator|manual|quick-add"
  tags: ["tag1", "tag2"]
  notes: "free text"
  blocked_reason: "reason if blocked"  # optional
  completed: "ISO timestamp"            # optional
```

### Task Lifecycle

```
pending → active → done
              ↓
          blocked
```

### Current Tasks

| ID | Status | Priority | Title |
|----|--------|----------|-------|
| 1 | ✅ done | high | Add structured task/project tracking |
| 2 | ✅ done | high | Add automatic session-close journaling |
| 3 | ✅ done | high | Create bootstrap installer for transferability |
| 4 | ▶ active | medium | Refine idea generation with knowledge graph |

---

## 🔁 Corrections Log

```
Location: corrections/corrections.yaml
CLI:      scripts/corrections.sh (installed as 'corrections')
```

### Schema

```yaml
- id: 1
  timestamp: "ISO timestamp"
  trigger: "What went wrong"
  correction: "What to do instead"
  applied: true/false
```

### All Corrections

| ID | Applied | Date | Trigger | Correction |
|----|---------|------|---------|------------|
| 1 | ✅ | $(date -u +%Y-%m-%d) | Told user URL instead of opening browser | Open browser myself and navigate there |

When `applied: true`, the correction is written to `AGENTS.md` as a permanent learned rule.

### How to Add

```bash
corrections log "what went wrong" "what to do instead" --apply
```

---

## 🎙 Voice CLI (yumehiru)

```
Location: kotlin-app/yumehiru (shell)
Symlink:  /usr/local/bin/yumehiru
```

| Command | Function | TTS |
|---------|----------|-----|
| `yumehiru` | Dashboard overview | — |
| `yumehiru status` | System health | — |
| `yumehiru tasks` | Task list | — |
| `yumehiru alerts` | Current alerts | — |
| `yumehiru speak` | Speak status aloud | ✅ |
| `yumehiru speak <text>` | Speak custom text | ✅ |
| `yumehiru watch` | Live alert monitoring | ✅ |

---

## 📂 Complete File Structure

```
/root/.openclaw/workspace/
├── AGENTS.md              # Operational rules + learned corrections
├── SOUL.md                # Personality & tone
├── IDENTITY.md            # Identity (Yumehiru)
├── USER.md                # User profile & fine-tuning levers
├── TOOLS.md               # Environment notes
├── HEARTBEAT.md           # Heartbeat configuration
├── .gitignore             # Git ignore rules
│
├── agents/
│   ├── idea-generator/
│   │   ├── AGENTS.md
│   │   ├── generate.sh           # Every 15 min → ideas via local LLM
│   │   ├── cron.log
│   │   ├── state/
│   │   │   ├── current.md         # Generation state
│   │   │   └── latest-suggestion.md
│   │   └── history/               # Archived suggestions
│   │
│   ├── idea-executor/
│   │   ├── AGENTS.md
│   │   ├── execute.sh             # Every 2 min → implement tasks
│   │   ├── executor-cron.log
│   │   ├── state/processed.md
│   │   └── logs/                  # Execution logs
│   │
│   ├── local-llm/
│   │   └── llm.sh                 # Server wrapper
│   │
│   └── tools/
│       ├── tool-server.py          # Python tool server
│       └── tools.sh                # Shell wrapper
│
├── scripts/
│   ├── taskctl.sh                  # Task management CLI
│   ├── corrections.sh             # Corrections system
│   ├── session-close.sh           # Memory journaling
│   ├── setup.sh                   # Bootstrap installer
│   └── session-close.log
│
├── tasks/
│   ├── README.md
│   ├── tasks.yaml                 # Master task manifest
│   ├── active/
│   ├── pending/
│   ├── blocked/
│   ├── done/
│   └── archive/
│
├── corrections/
│   ├── README.md
│   └── corrections.yaml           # Learned behaviors
│
├── memory/
│   ├── YYYY-MM-DD.md              # Daily session logs
│   └── corrections.md             # Corrections memory
│
├── kotlin-app/
│   ├── yumehiru                   # Voice CLI executable
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   ├── YumehiruCli.main.kts
│   ├── README.md
│   └── src/main/kotlin/
│       ├── YumehiruApp.kt         # Compose Desktop UI
│       ├── ApiClient.kt           # Ktor HTTP client
│       ├── Models.kt              # Data models
│       └── TTS.kt                 # Text-to-speech
│
├── agents/dashboard/
│   ├── server.py                  # Dashboard web server
│   └── uploads/                   # Uploaded images
│
├── .venv/                         # Python virtual env
│   └── ... (26 packages)
│
└── exports/                       # Exported docs
```

---

## 📊 System Resources

| Resource | Usage |
|----------|-------|
| RAM | $(free -h | grep Mem | awk '{print $3"/"$2}') |
| Disk | $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}') |
| CPU | $(nproc) cores |
| OS | Linux $(uname -r) x86_64 |
| Python | $(python3 --version 2>/dev/null || echo "3.12") |
| Node | $(node --version 2>/dev/null || echo "v24") |
| Model | Llama 3.2 3B Instruct Q4_K_M (1.9 GB) |

---

## 🔌 API Endpoints

### Dashboard API (port 18082)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Full HTML dashboard |
| GET | `/api/tasks` | List all tasks |
| POST | `/api/tasks` | Create task |
| PUT | `/api/tasks/:id` | Update task (start/done/block/unblock) |
| GET | `/api/status` | System health (services, RAM, disk, cron) |
| GET | `/api/alerts` | Current alerts |
| GET | `/api/logs` | Recent activity logs |
| POST | `/api/llm` | Query local LLM |
| POST | `/api/upload` | Upload image → OCR + LLM analysis |
| GET/POST | `/api/corrections` | Corrections CRUD |

### LLM Server (port 18080)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Server health |
| POST | `/v1/chat/completions` | OpenAI-compatible chat |
| POST | `/v1/completions` | OpenAI-compatible completions |

### Tool Server (port 18081)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Server health |
| POST | `/web_search` | DuckDuckGo search |
| POST | `/run_python` | Execute Python |
| POST | `/fetch` | Fetch URL + extract text |
| POST | `/wikipedia` | Wikipedia lookup |

---

## 🔄 Data Flow

```
User Request
    │
    ▼
┌─────────────┐
│  Dashboard   │──► API ──► Sub-agent scripts ──► shell commands
│  (Web UI)    │                                   │
│  :18082      │                                   ▼
└─────────────┘                              File system changes
    │                                            │
    ▼                                            ▼
┌─────────────┐                           Update tasks.yaml
│  Voice CLI   │                           Update corrections.yaml
│  yumehiru    │                           Git commit
└─────────────┘                           Session journaling
    │
    ▼
┌─────────────┐
│  Local LLM   │──► Generate ideas → tasks → execute → done
│  llama-srv   │
│  :18080      │
└─────────────┘
    │
    ▼
┌─────────────┐
│  Tools       │──► Web search, Python, fetch
│  :18081      │
└─────────────┘
```

---

## 📝 Git Status

All workspace files are tracked. Run `git add -A && git commit -m "update"` to save state.

---

*Export generated $(date -u). For the live system, visit http://168.231.113.165:18082*
