#!/usr/bin/env python3
"""Yumehiru Tool Server — web search, python execution, URL fetching"""
import json
import subprocess
import sys
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from ddgs import DDGS
import wikipediaapi

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18081
VENV_PYTHON = "/root/.openclaw/workspace/.venv/bin/python3"

class ToolHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_cors()
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        if self.path == '/health':
            self.wfile.write(json.dumps({"status": "ok", "tools": ["web_search", "wikipedia", "run_python", "fetch"]}).encode())
        else:
            self.wfile.write(json.dumps({"error": "not found"}).encode())

    def send_cors(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Type', 'application/json')

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else b'{}'
        data = json.loads(body) if body else {}

        if self.path == '/web_search':
            result = self.web_search(data.get('query', ''), data.get('max', 5))
        elif self.path == '/wikipedia':
            result = self.wikipedia_summary(data.get('title', ''))
        elif self.path == '/run_python':
            result = self.run_python(data.get('code', ''), data.get('timeout', 10))
        elif self.path == '/fetch':
            result = self.fetch_url(data.get('url', ''))
        else:
            result = {"error": "unknown tool"}
            self.send_response(404)

        self.send_cors()
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())

    def web_search(self, query, max_results=5):
        try:
            with DDGS() as ddgs:
                results = list(ddgs.text(query, max_results=max_results))
            return {"results": [{"title": r.get('title', ''), "href": r.get('href', ''), "body": r.get('body', '')} for r in results]}
        except Exception as e:
            return {"error": str(e)}

    def wikipedia_summary(self, title):
        try:
            wiki = wikipediaapi.Wikipedia('Yumehiru/1.0', 'en')
            page = wiki.page(title)
            if not page.exists():
                # Try search
                with DDGS() as ddgs:
                    results = list(ddgs.text(f"wikipedia {title}", max_results=3))
                    return {"results": [{"title": r.get('title', ''), "href": r.get('href', ''), "body": r.get('body', '')} for r in results]}
            return {"title": page.title, "summary": page.summary[:2000], "url": page.fullurl}
        except Exception as e:
            return {"error": str(e)}

    def run_python(self, code, timeout=10):
        try:
            proc = subprocess.run(
                [VENV_PYTHON, '-c', code],
                capture_output=True, text=True, timeout=timeout
            )
            return {
                "stdout": proc.stdout[:5000],
                "stderr": proc.stderr[:2000],
                "exit_code": proc.returncode
            }
        except subprocess.TimeoutExpired:
            return {"error": f"execution timed out after {timeout}s"}
        except Exception as e:
            return {"error": str(e)}

    def fetch_url(self, url):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Yumehiru/1.0'})
            with urllib.request.urlopen(req, timeout=15) as resp:
                content = resp.read().decode('utf-8', errors='replace')
                # Extract text from HTML
                from bs4 import BeautifulSoup
                soup = BeautifulSoup(content, 'html.parser')
                for tag in soup(['script', 'style', 'nav', 'footer', 'header']):
                    tag.decompose()
                text = soup.get_text(separator='\n', strip=True)
                return {"text": text[:10000], "url": url, "status": resp.status}
        except Exception as e:
            return {"error": str(e)}

    def log_message(self, format, *args):
        pass  # Quiet

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', PORT), ToolHandler)
    print(f"[tool-server] Listening on :{PORT}")
    print(f"[tool-server] Tools: web_search, wikipedia, run_python, fetch")
    server.serve_forever()
