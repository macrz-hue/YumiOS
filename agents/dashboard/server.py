#!/usr/bin/env python3
"""Yumehiru Dashboard — task tracking, image upload, alerts"""
import json, os, subprocess, base64, io, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
from pathlib import Path

PORT = int(os.environ.get('DASHBOARD_PORT', '18082'))
WORKSPACE = Path('/root/.openclaw/workspace')
TASKS_FILE = WORKSPACE / 'tasks' / 'tasks.yaml'
UPLOAD_DIR = WORKSPACE / 'agents' / 'dashboard' / 'uploads'
LLM_URL = 'http://127.0.0.1:18080/v1/chat/completions'
TOOL_URL = 'http://127.0.0.1:18081'
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

class DashboardHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        if self.path == '/' or self.path == '/dashboard':
            self.serve_html()
        elif self.path == '/export':
            self.serve_export()
        elif self.path == '/api/tasks':
            self.send_json(self.get_tasks())
        elif self.path == '/api/status':
            self.send_json(self.get_status())
        elif self.path == '/api/alerts':
            self.send_json(self.get_alerts())
        elif self.path.startswith('/uploads/'):
            self.serve_upload()
        elif self.path == '/api/logs':
            self.send_json(self.get_recent_logs())
        elif self.path == '/api/corrections':
            self.send_json(self.get_corrections())
        else:
            self.send_json({'error': 'not found'}, 404)

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b'{}'
        
        if self.path == '/api/tasks':
            data = json.loads(body)
            result = self.create_task(data)
            self.send_json(result)
        elif self.path == '/api/upload':
            self.handle_upload(body)
        elif self.path == '/api/llm':
            data = json.loads(body)
            result = self.call_llm(data)
            self.send_json(result)
        elif self.path == '/api/corrections':
            data = json.loads(body)
            result = self.log_correction(data)
            self.send_json(result)
        else:
            self.send_json({'error': 'not found'}, 404)

    def do_PUT(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b'{}'
        
        if self.path.startswith('/api/tasks/'):
            tid = self.path.split('/')[-1]
            data = json.loads(body)
            result = self.update_task(tid, data)
            self.send_json(result)
        else:
            self.send_json({'error': 'not found'}, 404)

    def send_cors(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Type', 'application/json')
        self.end_headers()

    def send_json(self, data, code=200):
        self.send_response(code)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        try:
            self.wfile.write(json.dumps(data).encode())
        except BrokenPipeError:
            pass

    def serve_export(self):
        try:
            content = open('/root/.openclaw/workspace/exports/index.html').read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(content.encode())
        except Exception as e:
            self.send_json({'error': str(e)}, 500)

    def serve_html(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        html = self.build_dashboard()
        self.wfile.write(html.encode())

    def serve_upload(self):
        path = UPLOAD_DIR / self.path.split('/uploads/')[-1]
        if path.exists():
            self.send_response(200)
            ext = path.suffix.lower()
            mime = {'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp'}
            self.send_header('Content-Type', mime.get(ext.lstrip('.'), 'application/octet-stream'))
            self.end_headers()
            self.wfile.write(path.read_bytes())
        else:
            self.send_json({'error': 'not found'}, 404)

    # ─── API Methods ────────────────────────────────────────

    def get_tasks(self):
        if not TASKS_FILE.exists():
            return {'tasks': []}
        try:
            tasks = json.loads(TASKS_FILE.read_text())
            return {'tasks': tasks}
        except: return {'tasks': [], 'error': 'parse error'}

    def get_status(self):
        services = {}
        for name, port in [('llama-server', 18080), ('tool-server', 18081), ('dashboard', 18082)]:
            try:
                r = urllib.request.urlopen(f'http://127.0.0.1:{port}/health', timeout=2)
                services[name] = 'ok' if r.status == 200 else 'error'
            except: services[name] = 'down'
        
        # Cron
        cron = subprocess.run(['crontab', '-l'], capture_output=True, text=True, timeout=5)
        cron_count = len([l for l in cron.stdout.split('\n') if l and not l.startswith('#')])
        
        # Memory
        mem = subprocess.run(['free', '-h'], capture_output=True, text=True, timeout=5)
        mem_line = mem.stdout.split('\n')[1].split()
        
        # Disk
        disk = subprocess.run(['df', '-h', '/'], capture_output=True, text=True, timeout=5)
        disk_line = disk.stdout.split('\n')[1].split()
        
        return {
            'services': services,
            'cron_jobs': cron_count,
            'memory': f"{mem_line[2]}/{mem_line[1]}" if len(mem_line) > 2 else 'unknown',
            'disk': f"{disk_line[2]}/{disk_line[1]}" if len(disk_line) > 2 else 'unknown',
            'uptime': subprocess.run(['uptime', '-p'], capture_output=True, text=True, timeout=5).stdout.strip()
        }

    def get_alerts(self):
        alerts = []
        try:
            tasks = json.loads(TASKS_FILE.read_text()) if TASKS_FILE.exists() else []
            # Urgent: high priority + active or blocked >12h
            for t in tasks:
                if t.get('priority') == 'high' and t.get('status') in ('active', 'blocked'):
                    alerts.append({
                        'type': 'urgent',
                        'task_id': t['id'],
                        'message': f"High priority task #{t['id']}: {t['title']}",
                        'status': t['status']
                    })
                if t.get('status') == 'blocked':
                    alerts.append({
                        'type': 'blocked',
                        'task_id': t['id'],
                        'message': f"Blocked: #{t['id']} {t['title']}",
                        'reason': t.get('blocked_reason', 'unknown')
                    })
        except: pass
        
        # Check for recent failures
        log_file = WORKSPACE / 'agents/idea-executor/executor-cron.log'
        if log_file.exists():
            lines = log_file.read_text().split('\n')[-20:]
            fails = [l for l in lines if '❌' in l or 'failed' in l.lower() or 'error' in l.lower()]
            alerts.extend([{'type': 'error', 'message': f.strip()} for f in fails[-3:]])
        
        return {'alerts': alerts[:10]}

    def get_recent_logs(self):
        logs = []
        log_files = [
            WORKSPACE / 'agents/idea-generator/cron.log',
            WORKSPACE / 'agents/idea-executor/executor-cron.log',
            WORKSPACE / 'scripts/session-close.log'
        ]
        for lf in log_files:
            if lf.exists():
                lines = lf.read_text().split('\n')[-10:]
                name = lf.parent.name
                logs.append({'source': name, 'lines': [l for l in lines if l]})
        return {'logs': logs}

    def create_task(self, data):
        title = data.get('title', 'Untitled')
        priority = data.get('priority', 'medium')
        tags = data.get('tags', 'manual')
        
        result = subprocess.run(
            [str(WORKSPACE / 'scripts/taskctl.sh'), 'add', title, priority, tags],
            capture_output=True, text=True, timeout=10
        )
        return {'result': result.stdout.strip(), 'error': result.stderr.strip() or None}

    def update_task(self, tid, data):
        action = data.get('action', '')
        valid = {'start', 'done', 'block', 'unblock'}
        if action in valid:
            reason = data.get('reason', '')
            cmd = [str(WORKSPACE / 'scripts/taskctl.sh'), action, tid]
            if action == 'block' and reason:
                cmd.append(reason)
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            return {'result': result.stdout.strip(), 'error': result.stderr.strip() or None}
        return {'error': f'invalid action: {action}'}

    def get_corrections(self):
        import subprocess
        try:
            r = subprocess.run(['/usr/local/bin/corrections', 'list'], capture_output=True, text=True, timeout=10)
            out = r.stdout
            # Also get the raw JSON
            with open('/root/.openclaw/workspace/corrections/corrections.yaml') as f:
                import json
                data = json.load(f)
            return {'corrections': data, 'text': out}
        except Exception as e:
            return {'corrections': [], 'text': str(e)}

    def log_correction(self, data):
        import subprocess
        trigger = data.get('trigger', '')
        correction = data.get('correction', '')
        apply = data.get('apply', False)
        if not trigger or not correction:
            return {'error': 'trigger and correction required'}
        cmd = ['/usr/local/bin/corrections', 'log', trigger, correction]
        if apply:
            cmd.append('--apply')
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            return {'result': r.stdout.strip(), 'error': r.stderr.strip() or None}
        except Exception as e:
            return {'error': str(e)}

    def call_llm(self, data):
        prompt = data.get('prompt', '')
        messages = [{"role": "user", "content": prompt}]
        system = data.get('system', '')
        if system:
            messages.insert(0, {"role": "system", "content": system})
        
        try:
            req = urllib.request.Request(LLM_URL,
                data=json.dumps({"messages": messages, "max_tokens": 512, "temperature": 0.7}).encode(),
                headers={'Content-Type': 'application/json'})
            resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
            return {'response': resp['choices'][0]['message']['content']}
        except Exception as e:
            return {'error': str(e)}

    def handle_upload(self, body):
        import cgi, io
        content_type = self.headers.get('Content-Type', '')
        
        if 'image' in content_type:
            # Raw image upload
            ext = 'png'
            if 'jpeg' in content_type: ext = 'jpg'
            elif 'gif' in content_type: ext = 'gif'
            elif 'webp' in content_type: ext = 'webp'
            
            fname = f"upload-{datetime.now().strftime('%Y%m%d-%H%M%S')}.{ext}"
            fpath = UPLOAD_DIR / fname
            fpath.write_bytes(body)
            
            # OCR the image
            text = self.ocr_image(fpath)
            
            # Ask LLM about it
            prompt = f"An image was uploaded. OCR extracted this text: {text[:1000]}\n\nWhat can you tell me about this?"
            analysis = self.llm_quick(prompt)
            
            self.send_json({
                'filename': fname,
                'url': f'/uploads/{fname}',
                'ocr_text': text[:2000],
                'analysis': analysis
            })
        else:
            # Form upload
            env = {'REQUEST_METHOD': 'POST', 'CONTENT_TYPE': content_type}
            fs = cgi.FieldStorage(io.BytesIO(body), environ=env)
            if 'image' in fs:
                f = fs['image']
                fname = f"upload-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{f.filename or 'img.png'}"
                fpath = UPLOAD_DIR / fname
                fpath.write_bytes(f.file.read())
                
                text = self.ocr_image(fpath)
                analysis = self.llm_quick(f"OCR: {text[:1000]}\n\nDescribe contents:")
                self.send_json({
                    'filename': fname, 'url': f'/uploads/{fname}',
                    'ocr_text': text[:2000], 'analysis': analysis
                })
            else:
                self.send_json({'error': 'no image field'}, 400)

    def ocr_image(self, path):
        try:
            from PIL import Image
            import pytesseract
            img = Image.open(path)
            text = pytesseract.image_to_string(img)
            return text.strip() or '(no text detected)'
        except Exception as e:
            return f'(OCR error: {e})'

    def llm_quick(self, prompt):
        try:
            req = urllib.request.Request(LLM_URL,
                data=json.dumps({
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": 256, "temperature": 0.5
                }).encode(),
                headers={'Content-Type': 'application/json'})
            resp = json.loads(urllib.request.urlopen(req, timeout=30).read())
            return resp['choices'][0]['message']['content']
        except: return '(analysis unavailable)'

    def build_dashboard(self):
        """Inline single-page dashboard HTML"""
        return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Yumehiru Dashboard</title>
<style>
:root { --bg: #0f0f14; --card: #1a1a24; --border: #2a2a3a; --text: #e0e0e8; --accent: #7c5cfc; --urgent: #ff4444; --green: #44cc88; --yellow: #ffcc44; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); padding: 20px; }
.container { max-width: 1200px; margin: 0 auto; }
.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
.header h1 { font-size: 24px; }
.header h1 span { color: var(--accent); }
.status-dots { display: flex; gap: 12px; font-size: 13px; }
.dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
.dot.ok { background: var(--green); }
.dot.error { background: var(--urgent); }
.dot.down { background: #555; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; }
.card { background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 16px; }
.card h2 { font-size: 14px; text-transform: uppercase; letter-spacing: 1px; color: #888; margin-bottom: 12px; }
.card-full { grid-column: 1 / -1; }
.task-row { display: flex; align-items: center; padding: 8px 0; border-bottom: 1px solid var(--border); gap: 8px; font-size: 14px; }
.task-row:last-child { border: none; }
.badge { font-size: 11px; padding: 2px 8px; border-radius: 4px; }
.badge-high { background: #442200; color: var(--yellow); }
.badge-medium { background: #002244; color: #44aaff; }
.badge-low { background: #222; color: #888; }
.badge-active { background: #003322; color: var(--green); }
.badge-pending { background: #222244; color: #8888ff; }
.badge-done { background: #112211; color: #66aa66; }
.badge-blocked { background: #440000; color: var(--urgent); }
.btn { background: var(--accent); color: white; border: none; padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 13px; }
.btn:hover { opacity: 0.85; }
.btn-sm { padding: 3px 10px; font-size: 12px; }
.btn-danger { background: #662222; }
input, textarea, select { background: #222; border: 1px solid var(--border); color: var(--text); padding: 8px 12px; border-radius: 6px; font-size: 14px; width: 100%; }
textarea { resize: vertical; min-height: 80px; font-family: monospace; }
.flex { display: flex; gap: 8px; align-items: center; }
.flex-wrap { flex-wrap: wrap; }
.mt-8 { margin-top: 8px; }
.mt-16 { margin-top: 16px; }
.mb-8 { margin-bottom: 8px; }
.gap-4 { gap: 4px; }
.text-center { text-align: center; }
.text-muted { color: #888; font-size: 13px; }
.alert-item { padding: 8px 0; border-bottom: 1px solid var(--border); font-size: 13px; display: flex; align-items: center; gap: 8px; }
.alert-urgent { border-left: 3px solid var(--urgent); padding-left: 8px; }
.alert-blocked { border-left: 3px solid var(--yellow); padding-left: 8px; }
.alert-error { border-left: 3px solid var(--urgent); padding-left: 8px; }
.upload-area { border: 2px dashed var(--border); border-radius: 8px; padding: 24px; text-align: center; cursor: pointer; transition: all 0.2s; }
.upload-area:hover { border-color: var(--accent); background: #1a1a2a; }
.upload-result { margin-top: 12px; padding: 12px; background: #111; border-radius: 8px; font-size: 13px; max-height: 200px; overflow-y: auto; }
.upload-result img { max-width: 100%; max-height: 150px; border-radius: 4px; margin-bottom: 8px; }
.log-line { font-family: monospace; font-size: 12px; padding: 2px 0; color: #888; }
.log-line:first-child { padding-top: 0; }
.tab-bar { display: flex; gap: 0; margin-bottom: 12px; }
.tab { padding: 8px 16px; cursor: pointer; border-bottom: 2px solid transparent; font-size: 13px; color: #888; }
.tab.active { border-bottom-color: var(--accent); color: var(--text); }
.tab:hover { color: var(--text); }
.hidden { display: none; }
.columns { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; }
@media (max-width: 768px) { .grid, .columns { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>Yumehiru <span>Dashboard</span> 👻✨</h1>
    <div class="status-dots" id="statusDots"></div>
  </div>

  <div class="tab-bar">
    <div class="tab active" onclick="switchTab('tasks')">📋 Tasks</div>
    <div class="tab" onclick="switchTab('upload')">📷 Upload</div>
    <div class="tab" onclick="switchTab('alerts')">🔔 Alerts</div>
    <div class="tab" onclick="switchTab('status')">📊 System</div>
    <div class="tab" onclick="switchTab('corrections')">🔧 Corr</div>
    <div class="tab" onclick="window.location.href='/export'">📄 Export</div>
  </div>

  <!-- Tasks Tab -->
  <div id="tab-tasks" class="grid">
    <div class="card">
      <h2>New Task</h2>
      <input id="newTaskTitle" placeholder="Task title..." class="mb-8">
      <div class="flex mb-8">
        <select id="newTaskPriority" style="flex:1">
          <option value="high">High</option>
          <option value="medium" selected>Medium</option>
          <option value="low">Low</option>
        </select>
        <input id="newTaskTags" placeholder="tags (comma)" style="flex:1">
      </div>
      <button class="btn" onclick="createTask()">+ Add Task</button>
    </div>
    <div class="card">
      <h2>Quick Actions</h2>
      <div class="flex flex-wrap gap-4">
        <button class="btn btn-sm" onclick="runAction('start', nextTaskId())">▶ Start Next</button>
        <button class="btn btn-sm" onclick="refreshAll()">🔄 Refresh</button>
        <button class="btn btn-sm" onclick="callLLM()">🤖 Ask LLM</button>
      </div>
      <div id="quickResult" class="text-muted mt-8"></div>
    </div>
    <div class="card card-full">
      <h2>Task Board</h2>
      <div class="columns" id="taskBoard"></div>
    </div>
  </div>

  <!-- Upload Tab -->
  <div id="tab-upload" class="hidden">
    <div class="card">
      <h2>Upload Image for Analysis</h2>
      <div class="upload-area" onclick="document.getElementById('fileInput').click()" id="uploadArea">
        <p>Drop an image here or click to upload</p>
        <p class="text-muted mt-8">Supported: PNG, JPG, GIF, WebP</p>
      </div>
      <input type="file" id="fileInput" accept="image/*" style="display:none" onchange="uploadFile(this)">
      <div id="uploadResult" class="upload-result hidden"></div>
    </div>
  </div>

  <!-- Alerts Tab -->
  <div id="tab-alerts" class="hidden">
    <div class="card card-full">
      <div class="flex" style="justify-content: space-between;">
        <h2>Alerts & Notifications</h2>
        <button class="btn btn-sm" onclick="loadAlerts()">🔄 Refresh</button>
      </div>
      <div id="alertList">
        <p class="text-muted text-center">Loading alerts...</p>
      </div>
    </div>
  </div>

  <!-- System Tab -->
  <div id="tab-status" class="hidden">
  <div id="tab-corrections" class="hidden">
    <div class="card card-full">
      <div class="flex" style="justify-content: space-between;">
        <h2>Corrections Log — Things Yumehiru Has Learned</h2>
        <button class="btn btn-sm" onclick="loadCorrections()">🔄 Refresh</button>
      </div>
      <div class="mb-16">
        <h3>Log a New Correction</h3>
        <input id="corrTrigger" placeholder="What went wrong..." class="mb-8" style="width:100%">
        <textarea id="corrCorrect" placeholder="What I should do instead..." style="width:100%" rows="2"></textarea>
        <div class="flex mt-8">
          <button class="btn" onclick="logCorrection()">📝 Log &amp; Apply</button>
          <span id="corrResult" class="text-muted" style="margin-left:12px"></span>
        </div>
      </div>
      <div id="correctionsList"></div>
    </div>
  </div>
    <div class="grid">
      <div class="card">
        <h2>Services</h2>
        <div id="serviceList"></div>
      </div>
      <div class="card">
        <h2>Resources</h2>
        <div id="resourceList"></div>
      </div>
      <div class="card">
        <h2>Cron Jobs</h2>
        <div id="cronInfo"></div>
      </div>
      <div class="card">
        <h2>LLM Query</h2>
        <textarea id="llmPrompt" placeholder="Ask Yumehiru anything..."></textarea>
        <button class="btn mt-8" onclick="callLLM()">Ask</button>
        <div id="llmResult" class="mt-8 text-muted"></div>
      </div>
      <div class="card card-full">
        <h2>Recent Activity</h2>
        <div id="recentLogs"></div>
      </div>
    </div>
  </div>
</div>

<script>
let tasks = [];
let nextId = 1;

function switchTab(name) {
  document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('[id^="tab-"]').forEach(t => t.classList.add('hidden'));
  document.querySelector(`.tab[onclick*="${name}"]`).classList.add('active');
  document.getElementById(`tab-${name}`).classList.remove('hidden');
  if (name === 'tasks') loadTasks();
  if (name === 'alerts') loadAlerts();
  if (name === 'status') loadStatus();
}

async function api(path, opts = {}) {
  const resp = await fetch(path, {
    headers: {'Content-Type': 'application/json'},
    ...opts
  });
  return resp.json();
}

function nextTaskId() {
  if (tasks.length === 0) return 1;
  return Math.max(...tasks.map(t => t.id)) + 1;
}

// ─── Tasks ───────────────────────────────
async function loadTasks() {
  const data = await api('/api/tasks');
  tasks = data.tasks || [];
  renderTaskBoard();
  renderStatusDots();
}

function renderTaskBoard() {
  const board = document.getElementById('taskBoard');
  const cols = {pending: [], active: [], done: [], blocked: []};
  tasks.forEach(t => { cols[t.status] = cols[t.status] || []; cols[t.status].push(t); });
  
  board.innerHTML = ['pending', 'active', 'done'].map(status => {
    const items = (cols[status] || []).sort((a,b) => {
      const p = {high:0, medium:1, low:2};
      return (p[a.priority]||1) - (p[b.priority]||1) || a.id - b.id;
    });
    return `<div><h3 style="font-size:12px;text-transform:uppercase;color:#888;margin-bottom:8px">${status.toUpperCase()} (${items.length})</h3>
      ${items.map(t => renderTaskCard(t)).join('')}
      ${items.length === 0 ? '<p class="text-muted">Empty</p>' : ''}</div>`;
  }).join('');
}

function renderTaskCard(t) {
  const pClass = {'high':'badge-high','medium':'badge-medium','low':'badge-low'}[t.priority] || '';
  const sClass = {'active':'badge-active','pending':'badge-pending','done':'badge-done','blocked':'badge-blocked'}[t.status] || '';
  return `<div class="task-row" style="flex-direction:column;align-items:stretch;background:#15151e;border-radius:8px;padding:10px;margin-bottom:6px">
    <div class="flex" style="justify-content:space-between;width:100%">
      <strong>#${t.id}</strong>
      <div class="flex gap-4">
        <span class="badge ${pClass}">${t.priority}</span>
      </div>
    </div>
    <div style="font-size:13px;margin:4px 0">${t.title}</div>
    <div class="flex flex-wrap gap-4">
      ${t.status === 'pending' ? `<button class="btn btn-sm" onclick="updateTask(${t.id},'start')">▶ Start</button>` : ''}
      ${t.status === 'active' ? `<button class="btn btn-sm" onclick="updateTask(${t.id},'done')">✓ Done</button>` : ''}
      ${t.status !== 'done' && t.status !== 'blocked' ? `<button class="btn btn-sm btn-danger" onclick="blockTask(${t.id})">⛔ Block</button>` : ''}
      ${t.status === 'blocked' ? `<button class="btn btn-sm" onclick="updateTask(${t.id},'unblock')">↻ Unblock</button>` : ''}
      <span class="badge ${sClass}">${t.status}</span>
    </div>
    ${t.blocked_reason ? `<div class="text-muted mt-8" style="font-size:12px">⚠ ${t.blocked_reason}</div>` : ''}
  </div>`;
}

async function createTask() {
  const title = document.getElementById('newTaskTitle').value.trim();
  if (!title) return;
  const priority = document.getElementById('newTaskPriority').value;
  const tags = document.getElementById('newTaskTags').value || 'manual';
  await api('/api/tasks', {method: 'POST', body: JSON.stringify({title, priority, tags})});
  document.getElementById('newTaskTitle').value = '';
  loadTasks();
}

async function updateTask(id, action) {
  await api(`/api/tasks/${id}`, {method: 'PUT', body: JSON.stringify({action})});
  loadTasks();
}

async function blockTask(id) {
  const reason = prompt('Reason for blocking:');
  if (reason) {
    await api(`/api/tasks/${id}`, {method: 'PUT', body: JSON.stringify({action: 'block', reason})});
    loadTasks();
  }
}

// ─── Upload ──────────────────────────────
async function uploadFile(input) {
  const file = input.files[0];
  if (!file) return;
  
  const result = document.getElementById('uploadResult');
  result.classList.remove('hidden');
  result.innerHTML = '<p>Uploading...</p>';
  
  const formData = new FormData();
  formData.append('image', file);
  
  try {
    const resp = await fetch('/api/upload', {method: 'POST', body: formData});
    const data = await resp.json();
    
    if (data.error) {
      result.innerHTML = `<p class="text-muted">Error: ${data.error}</p>`;
      return;
    }
    
    result.innerHTML = `
      <img src="${data.url}" alt="Upload">
      <div class="flex"><strong>OCR Text:</strong> <span class="text-muted">${data.ocr_text || '(none)'}</span></div>
      <div class="mt-8"><strong>Analysis:</strong><br><span class="text-muted">${data.analysis || '(pending)'}</span></div>
    `;
  } catch(e) {
    result.innerHTML = `<p class="text-muted">Upload failed: ${e.message}</p>`;
  }
}

// Handle drag & drop
document.addEventListener('DOMContentLoaded', () => {
  const area = document.getElementById('uploadArea');
  if (!area) return;
  area.addEventListener('dragover', e => { e.preventDefault(); area.style.borderColor = 'var(--accent)'; });
  area.addEventListener('dragleave', () => { area.style.borderColor = ''; });
  area.addEventListener('drop', e => {
    e.preventDefault();
    area.style.borderColor = '';
    const file = e.dataTransfer.files[0];
    if (file) { document.getElementById('fileInput').files = e.dataTransfer.files; uploadFile(document.getElementById('fileInput')); }
  });
});

// ─── Alerts ──────────────────────────────
async function loadAlerts() {
  const data = await api('/api/alerts');
  const list = document.getElementById('alertList');
  const alerts = data.alerts || [];
  
  if (alerts.length === 0) {
    list.innerHTML = '<p class="text-muted text-center">No alerts. All clear! ✨</p>';
    return;
  }
  
  list.innerHTML = alerts.map(a => {
    const cls = a.type === 'urgent' ? 'alert-urgent' : a.type === 'blocked' ? 'alert-blocked' : 'alert-error';
    const icon = a.type === 'urgent' ? '🔴' : a.type === 'blocked' ? '🟡' : '🔴';
    return `<div class="alert-item ${cls}"><span>${icon}</span> <span>${a.message}</span></div>`;
  }).join('');
}

// ─── Status ──────────────────────────────
async function loadStatus() {
  const data = await api('/api/status');
  
  // Services
  const sl = document.getElementById('serviceList');
  sl.innerHTML = Object.entries(data.services || {}).map(([name, status]) => {
    const cls = status === 'ok' ? 'ok' : status === 'down' ? 'down' : 'error';
    return `<div class="flex mb-8"><span class="dot ${cls}"></span> ${name}</div>`;
  }).join('');
  
  // Resources
  const rl = document.getElementById('resourceList');
  rl.innerHTML = `
    <div class="mb-8">🧠 Memory: ${data.memory || '?'}</div>
    <div class="mb-8">💾 Disk: ${data.disk || '?'}</div>
    <div class="mb-8">🕐 ${data.uptime || '?'}</div>
  `;
  
  // Cron
  document.getElementById('cronInfo').innerHTML = `<div class="mb-8">⏰ ${data.cron_jobs || 0} cron jobs active</div>`;
  
  renderStatusDots();
}

function renderStatusDots() {
  const dots = document.getElementById('statusDots');
  const counts = {pending: 0, active: 0, blocked: 0, done: 0};
  tasks.forEach(t => { counts[t.status] = (counts[t.status] || 0) + 1; });
  dots.innerHTML = `
    <span><span class="dot" style="background:#8888ff"></span> ${counts.pending||0} pending</span>
    <span><span class="dot ok"></span> ${counts.active||0} active</span>
    <span><span class="dot" style="background:var(--urgent)"></span> ${counts.blocked||0} blocked</span>
    <span><span class="dot" style="background:#66aa66"></span> ${counts.done||0} done</span>
  `;
}

// ─── LLM ─────────────────────────────────
async function callLLM() {
  const prompt = document.getElementById('llmPrompt')?.value || 'What are you working on? Describe the current system status.';
  const result = document.getElementById('llmResult') || document.getElementById('quickResult');
  result.innerHTML = 'Thinking...';
  
  const data = await api('/api/llm', {method: 'POST', body: JSON.stringify({prompt})});
  result.innerHTML = data.response ? `<div style="background:#111;padding:8px;border-radius:6px;font-size:13px">${data.response}</div>` : `<span class="text-muted">${data.error || 'no response'}</span>`;
}

// ─── Logs ────────────────────────────────
async function loadLogs() {
  const data = await api('/api/logs');
  const el = document.getElementById('recentLogs');
  el.innerHTML = (data.logs || []).map(g => 
    `<div class="mb-8"><strong>${g.source}</strong>${g.lines.map(l => `<div class="log-line">${l}</div>`).join('')}</div>`
  ).join('') || '<p class="text-muted">No logs yet</p>';
}

async function loadCorrections() {
  const data = await api('/api/corrections');
  const list = document.getElementById('correctionsList');
  const corrs = data.corrections || [];
  if (corrs.length === 0) {
    list.innerHTML = '<p class="text-muted text-center">No corrections logged yet.</p>';
    return;
  }
  list.innerHTML = corrs.slice().reverse().map(c => {
    const icon = c.applied ? '✅' : '⏳';
    return `<div class="task-row" style="flex-direction:column;align-items:stretch">
      <div class="flex" style="justify-content:space-between;width:100%">
        <strong>#${c.id} ${icon}</strong>
        <span class="text-muted">${(c.timestamp||'').slice(0,16)}</span>
      </div>
      <div class="mt-8" style="font-size:13px"><strong>Trigger:</strong> ${c.trigger}</div>
      <div style="font-size:13px;color:var(--green)"><strong>Correction:</strong> ${c.correction}</div>
      <div class="text-muted mt-8" style="font-size:12px">Applied: ${c.applied ? 'Yes' : 'No'}</div>
    </div>`;
  }).join('');
}

async function logCorrection() {
  const trigger = document.getElementById('corrTrigger').value.trim();
  const correction = document.getElementById('corrCorrect').value.trim();
  if (!trigger || !correction) { document.getElementById('corrResult').textContent = 'Both fields required'; return; }
  document.getElementById('corrResult').textContent = 'Logging...';
  const data = await api('/api/corrections', {method: 'POST', body: JSON.stringify({trigger, correction, apply: true})});
  document.getElementById('corrResult').textContent = data.result || data.error || 'Done';
  document.getElementById('corrTrigger').value = '';
  document.getElementById('corrCorrect').value = '';
  loadCorrections();
}

function refreshAll() {
  loadTasks();
  loadAlerts();
  loadStatus();
  loadLogs();
  loadCorrections();
}

// ─── Init ────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  loadTasks();
  loadAlerts();
  loadStatus();
  loadLogs();
  loadCorrections();
  // Auto-refresh every 30s
  setInterval(refreshAll, 30000);
});
</script>
</body>
</html>"""
    def log_message(self, *a): pass

if __name__ == '__main__':
    srv = HTTPServer(('0.0.0.0', PORT), DashboardHandler)
    print(f"[dashboard] Listening on http://127.0.0.1:{PORT}")
    srv.serve_forever()
