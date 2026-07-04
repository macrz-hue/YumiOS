#!/usr/bin/env python3
"""yumehiru passwd — Set the admin password for YumiOS

Usage:
  yumehiru passwd                  # Prompt for password
  yumehiru passwd "my-secret"      # Set directly
  yumehiru passwd --check          # Check if password is set
"""
import json, hashlib, os, sys, getpass

PASSWD_FILE = "/root/.openclaw/workspace/.yumehiru-passwd"

def hash_pw(pw):
    return hashlib.sha256(pw.encode()).hexdigest()

def cmd_set(pw=None):
    if not pw:
        pw = getpass.getpass("Enter YumiOS admin password: ")
        confirm = getpass.getpass("Confirm: ")
        if pw != confirm:
            print("❌ Passwords don't match")
            sys.exit(1)
    if len(pw) < 4:
        print("❌ Password must be at least 4 characters")
        sys.exit(1)
    with open(PASSWD_FILE, "w") as f:
        json.dump({"hash": hash_pw(pw), "set": True}, f)
    os.chmod(PASSWD_FILE, 0o600)
    print("✅ YumiOS admin password set")

def cmd_check():
    if os.path.exists(PASSWD_FILE):
        with open(PASSWD_FILE) as f:
            data = json.load(f)
        if data.get("set"):
            print("✅ Admin password is set")
            return
    print("❌ No admin password set — run: yumehiru passwd")

def cmd_verify(pw):
    if not os.path.exists(PASSWD_FILE):
        print("❌ No password set")
        sys.exit(1)
    with open(PASSWD_FILE) as f:
        data = json.load(f)
    if data.get("hash") == hash_pw(pw):
        print("✅ Password verified")
        return True
    else:
        print("❌ Wrong password")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "passwd":
        pw = sys.argv[2] if len(sys.argv) > 2 else None
        cmd_set(pw)
    elif cmd == "--check":
        cmd_check()
    elif cmd == "--verify":
        cmd_verify(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        print(__doc__)
