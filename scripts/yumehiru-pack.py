#!/usr/bin/env python3
"""Yumehiru System Packager — Export & Deploy
One command to clone the entire system and spin it up anywhere.

USAGE:
  # On the source machine (this VPS):
  python3 yumehiru-pack.py export          # Create portable bundle
  python3 yumehiru-pack.py export --git    # Push to GitHub instead

  # On a target machine (fresh Linux box):
  python3 yumehiru-pack.py deploy bundle.tar.gz   # Deploy from bundle
  python3 yumehiru-pack.py deploy --git <url>     # Deploy from git
  python3 yumehiru-pack.py deploy --fresh         # Full bootstrap from scratch
"""

import json, os, shutil, subprocess, sys, tarfile, tempfile, textwrap
from pathlib import Path
from datetime import datetime

# ─── Paths ────────────────────────────────────────────────
WORKSPACE = Path("/root/.openclaw/workspace")
EXPORTS = WORKSPACE / "exports"
TIMESTAMP = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
BUNDLE_NAME = f"yumehiru-full-{TIMESTAMP}.tar.gz"
BUNDLE_PATH = EXPORTS / BUNDLE_NAME
VENV_PATH = WORKSPACE / ".venv"
EXPORT_DEPS = ["scripts", "agents", "tasks", "corrections", "memory", "kotlin-app", "exports"]
EXPORT_FILES = ["AGENTS.md", "SOUL.md", "IDENTITY.md", "USER.md", "TOOLS.md", "HEARTBEAT.md"]

log = lambda msg: print(f"[pack] {msg}")

# ═══════════════════════════════════════════════════════════
#  COMMAND: export
# ═══════════════════════════════════════════════════════════

def cmd_export(args):
    """Bundle everything into a portable archive."""
    use_git = "--git" in args
    git_url = None
    if "--git" in args:
        idx = args.index("--git")
        git_url = args[idx + 1] if len(args) > idx + 1 else None

    if use_git:
        export_to_git(git_url)
    else:
        export_to_bundle()

def export_to_bundle():
    """Create a .tar.gz bundle of the entire system."""
    log(f"Creating bundle: {BUNDLE_NAME}")
    EXPORTS.mkdir(parents=True, exist_ok=True)

    # Generate system manifest
    manifest = generate_manifest()

    with tarfile.open(BUNDLE_PATH, "w:gz") as tar:
        # Add manifest first
        add_to_tar(tar, "manifest.json", manifest.encode())

        # Add workspace files
        for name in EXPORT_DEPS:
            src = WORKSPACE / name
            if src.exists():
                for path in src.rglob("*"):
                    if not path.is_file() or should_skip(path):
                        continue
                    add_to_tar(tar, str(path.relative_to(WORKSPACE)), path.read_bytes())
                log(f"  Packed: {name}/")

        for name in EXPORT_FILES:
            src = WORKSPACE / name
            if src.exists():
                add_to_tar(tar, name, src.read_bytes())
                log(f"  Packed: {name}")

        # Add systemd service files
        for svc in ["llama-server", "yumehiru-tools", "yumehiru-dashboard"]:
            path = Path(f"/etc/systemd/system/{svc}.service")
            if path.exists():
                add_to_tar(tar, f"systemd/{svc}.service", path.read_bytes())
                log(f"  Packed: systemd/{svc}.service")

        # Add crontab
        cron = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        if cron.stdout.strip():
            add_to_tar(tar, "crontab.txt", cron.stdout.encode())
            log("  Packed: crontab.txt")

        # Add model info (just metadata, not the 2GB file)
        model_path = Path("/root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf")
        if model_path.exists():
            model_info = {
                "path": str(model_path),
                "size_bytes": model_path.stat().st_size,
                "size_human": f"{model_path.stat().st_size / 1024 / 1024 / 1024:.1f} GB",
                "url": "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                "download_cmd": "curl -L 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf' -o /root/.node-llama-cpp/models/llama-3.2-3b-instruct-q4_k_m.gguf"
            }
            add_to_tar(tar, "model-info.json", json.dumps(model_info, indent=2).encode())

        # Add dependency list
        deps = capture_dependencies()
        add_to_tar(tar, "dependencies.json", json.dumps(deps, indent=2).encode())

    size_mb = BUNDLE_PATH.stat().st_size / 1024 / 1024
    log(f"✅ Bundle created: {BUNDLE_NAME} ({size_mb:.1f} MB)")

    # Also create the bootstrap installer inline
    log(f"\n📋 To deploy on a new machine:")
    log(f"  1. Copy {BUNDLE_NAME} to the target machine")
    log(f"  2. Run: python3 yumehiru-pack.py deploy {BUNDLE_NAME}")
    log(f"")
    log(f"   Or extract manually:")
    log(f"  tar xzf {BUNDLE_NAME} && cd yumehiru-system && bash setup.sh")

def export_to_git(git_url):
    """Push the entire system to a git repo."""
    log("Preparing git export...")
    
    # Ensure git is initialized
    if not (WORKSPACE / ".git").exists():
        subprocess.run(["git", "init"], cwd=WORKSPACE, capture_output=True)
    
    # Write .gitignore
    gi = WORKSPACE / ".gitignore"
    gi.write_text(textwrap.dedent("""\
        .venv/
        __pycache__/
        *.pyc
        node_modules/
        .trash/
        *.gguf
        *.log
        .session-log.md
        .lock
        logs/
        cron.log
        executor-cron.log
        exports/*.tar.gz
    """))
    
    # Stage and commit
    subprocess.run(["git", "add", "-A"], cwd=WORKSPACE, capture_output=True)
    subprocess.run(["git", "commit", "--allow-empty", "-m", f"Yumehiru full export {TIMESTAMP}"], cwd=WORKSPACE, capture_output=True)
    
    if git_url:
        log(f"Pushing to {git_url}...")
        if "origin" not in subprocess.run(["git", "remote"], capture_output=True, text=True, cwd=WORKSPACE).stdout:
            subprocess.run(["git", "remote", "add", "origin", git_url], cwd=WORKSPACE, capture_output=True)
        subprocess.run(["git", "push", "-u", "origin", "main"], cwd=WORKSPACE)
        log(f"✅ Pushed to {git_url}")
        log(f"   Deploy: python3 yumehiru-pack.py deploy --git {git_url}")
    else:
        log("✅ Git repo ready (no remote set)")
        log(f"   git remote add origin <your-repo-url>")
        log(f"   git push -u origin main")

# ═══════════════════════════════════════════════════════════
#  COMMAND: deploy
# ═══════════════════════════════════════════════════════════

def cmd_deploy(args):
    """Deploy Yumehiru on a fresh machine from bundle or git."""
    is_fresh = "--fresh" in args
    use_git = "--git" in args
    git_url = None
    if "--git" in args:
        idx = args.index("--git")
        git_url = args[idx + 1] if len(args) > idx + 1 else None

    # Find the bundle path
    bundle_path = None
    for arg in args:
        if arg.endswith(".tar.gz") or arg.endswith(".tgz"):
            bundle_path = Path(arg)
            break

    log("🚀 Yumehiru Deployer")
    log("=" * 50)

    # If fresh, clone from git or extract bundle
    if is_fresh:
        # Create workspace
        WORKSPACE.mkdir(parents=True, exist_ok=True)
        
        if use_git and git_url:
            log(f"Cloning from {git_url}...")
            subprocess.run(["git", "clone", git_url, str(WORKSPACE)], check=True)
        elif bundle_path and bundle_path.exists():
            log(f"Extracting {bundle_path}...")
            with tarfile.open(bundle_path) as tar:
                tar.extractall(WORKSPACE)
        else:
            log("No bundle or git URL provided. Use --git <url> or specify a .tar.gz path")
            sys.exit(1)
        
        log("✅ Workspace extracted")
    
    # Run the setup/bootstrap
    setup_path = WORKSPACE / "scripts" / "setup.sh"
    if setup_path.exists():
        log("Running bootstrap installer...")
        subprocess.run(["bash", str(setup_path)], check=True)
    else:
        log("⚠️  No setup.sh found — running inline setup...")
        inline_setup()
    
    log("✅ Yumehiru deployment complete!")
    log(f"   Dashboard: http://$(hostname -I | awk '{{print $1}}'):18082")

def inline_setup():
    """Minimal inline bootstrap if setup.sh isn't available."""
    log("Creating workspace structure...")
    for d in ["scripts", "agents/idea-generator/state", "agents/idea-generator/history",
              "agents/idea-executor/state", "agents/idea-executor/logs", "agents/tools",
              "agents/local-llm", "tasks/pending", "tasks/done", "tasks/blocked",
              "tasks/archive", "corrections", "memory", "kotlin-app"]:
        (WORKSPACE / d).mkdir(parents=True, exist_ok=True)
    
    # Initialize task file
    (WORKSPACE / "tasks/tasks.yaml").write_text("[]")
    (WORKSPACE / "corrections/corrections.yaml").write_text("[]")
    
    log("To complete: run setup.sh or install dependencies manually")

# ═══════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════

def generate_manifest():
    """Create the system manifest JSON."""
    manifest = {
        "system": "Yumehiru",
        "version": "1.0.0",
        "exported_at": datetime.utcnow().isoformat(),
        "host": subprocess.run(["hostname"], capture_output=True, text=True).stdout.strip(),
        "git_commit": subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=WORKSPACE
        ).stdout.strip()[:12],
        "python_version": sys.version,
        "node_version": subprocess.run(["node", "--version"], capture_output=True, text=True).stdout.strip(),
        "llm_model": "Llama 3.2 3B Instruct Q4_K_M",
        "services": ["llama-server", "yumehiru-tools", "yumehiru-dashboard"],
        "cron_jobs": ["idea-generator (15min)", "idea-executor (2min)", "opsec (6h)", "session-close (6h)"],
        "state": {
            "tasks": read_json(WORKSPACE / "tasks/tasks.yaml", []),
            "corrections": read_json(WORKSPACE / "corrections/corrections.yaml", []),
        }
    }
    return json.dumps(manifest, indent=2)

def read_json(path, default):
    try:
        return json.loads(Path(path).read_text())
    except:
        return default

def should_skip(path):
    name = path.name
    return (name.startswith(".") and name not in [".gitignore", ".session-log.md"]) or \
           name.endswith(".pyc") or name.endswith(".log") or \
           ".venv" in str(path) or "node_modules" in str(path) or \
           "__pycache__" in str(path) or ".git" in str(path)

def add_to_tar(tar, name, data):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    info.mtime = int(datetime.utcnow().timestamp())
    tar.addfile(info, io.BytesIO(data) if isinstance(data, bytes) else io.BytesIO(data.encode()))

def capture_dependencies():
    """List all system dependencies."""
    deps = {
        "apt_packages": [],
        "python_packages": [],
        "services": [],
        "binaries": ["llama-server", "python3", "node", "git", "espeak-ng", "tesseract", "fail2ban-client"],
    }
    # APT packages
    try:
        r = subprocess.run(["apt", "list", "--installed", "2>/dev/null"], capture_output=True, text=True, shell=True)
        for line in r.stdout.split("\n")[1:]:
            if "/" in line:
                deps["apt_packages"].append(line.split("/")[0])
    except:
        pass
    # Python packages
    pip_list = Path(VENV_PATH) / "bin/pip"
    if pip_list.exists():
        r = subprocess.run([str(pip_list), "list", "--format=json"], capture_output=True, text=True)
        try:
            deps["python_packages"] = [p["name"] for p in json.loads(r.stdout)]
        except:
            pass
    return deps

# ═══════════════════════════════════════════════════════════
#  CLI ENTRY
# ═══════════════════════════════════════════════════════════

import io  # needed for BytesIO

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    cmd = sys.argv[1]
    args = sys.argv[2:]

    if cmd == "export":
        cmd_export(args)
    elif cmd == "deploy":
        cmd_deploy(args)
    elif cmd in ("--help", "-h", "help"):
        print(__doc__)
    else:
        print(f"Unknown command: {cmd}")
        print("Use: export | deploy | help")

if __name__ == "__main__":
    main()
