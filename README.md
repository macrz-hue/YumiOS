# 🚀 YumiOS — Your Autonomous AI Operating System

> A complete, self-hosted AI agent system. Runs entirely on your own machine. No cloud dependency, no subscriptions, no data leaving your network.

---

## ⚡ Quickstart (Windows — 2 commands)

Open **PowerShell as Administrator** and run:

```powershell
# 1. Deploy YumiOS to your machine
irm https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup-windows.ps1 | iex

# 2. Set your admin password
yumehiru passwd "your-secret-password"
```

That's it. The script will:

1. ✅ Install WSL2 + Ubuntu (if needed)
2. ✅ Clone YumiOS into `~/YumiOS`
3. ✅ Install Python + dependencies
4. ✅ Download the local LLM (~2 GB Llama 3.2 3B)
5. ✅ Start all services (llama-server, tools, dashboard)
6. ✅ Set up cron automation (idea generator, executor, opsec)

**After installation:** Open `http://localhost:18082` in your browser.

---

## ⚡ Quickstart (Linux — 1 command)

```bash
curl -sL https://github.com/macrz-hue/YumiOS/raw/main/scripts/setup.sh | bash
yumehiru passwd "your-secret-password"
```

---

## 🔧 What You Get

| Component | What it does |
|-----------|-------------|
| **Local LLM** | Llama 3.2 3B — runs offline, ~30 tok/s |
| **Dashboard** | Web UI at `:18082` — tasks, alerts, upload, LLM chat |
| **Task System** | Persistent tasks with lifecycle (pending→active→done) |
| **Idea Generator** | Every 15 min — suggests self-improvements |
| **Idea Executor** | Every 2 min — implements tasks automatically |
| **OpSec Agent** | Every 6h — security scans, auto-hardens firewall |
| **Voice CLI** | `yumehiru speak "status"` — TTS output via espeak |
| **Corrections** | Learn from mistakes — logged and wired permanently |
| **Web Search** | DuckDuckGo search, URL fetch, Python execution |
| **Universal LLM** | `yumehiru-llm "ask anything"` — auto fallback chain |
| **Packager** | `yumehiru-pack export` — portable system bundle |
| **Corrections** | `corrections log "error" "fix" --apply` — learns forever |

## 📁 Structure

```
~/.openclaw/workspace/
├── agents/          # Sub-agents (generator, executor, opsec, tools)
├── scripts/         # CLI tools (taskctl, corrections, setup, llm, pack)
├── tasks/           # Persistent task database
├── corrections/     # Learned behaviors database
├── memory/          # Session journaling
├── kotlin-app/      # Kotlin desktop app source
└── exports/         # System export bundles
```

## 🔐 Admin Password

Set or change the admin password anytime:

```bash
yumehiru passwd                    # Interactive prompt
yumehiru passwd "my-password"      # Direct set
yumehiru passwd --check            # Check if set
```

## 🌐 Web Dashboard

Once running, open in your browser:

```
http://localhost:18082
```

Tabs: Tasks, Upload, Alerts, System, Corrections, Export

## 📦 Export & Transfer

```bash
yumehiru-pack export                    # Create portable bundle
yumehiru-pack export --git <url>        # Push to git
yumehiru-pack deploy bundle.tar.gz      # Deploy on fresh machine
```

---

*YumiOS — Your second self, in software. Built by Yumehiru.* 👻✨
