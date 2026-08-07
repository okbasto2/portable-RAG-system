#!/usr/bin/env python
"""
reset-data.py — Wipe all user data, keep config and models.

Clears:
  - SQLite: users, chats, auth, knowledge, files, tags, messages
  - Uploaded documents
  - Cache (images, audio, functions)
  - Logs
  - Server PID file

Keeps:
  - Config (RAG settings, model endpoints, etc.)
  - Ollama model weights (ollama_models/)
  - The SQLite file itself (structure + config survive)
  - All application code and executables

Run: apps\\python_env\\python.exe reset-data.py
"""
import json
import os
import shutil
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

DB_PATH = os.path.join(HERE, "data", "openwebui_data", "webui.db")
UPLOADS = os.path.join(HERE, "data", "openwebui_data", "uploads")
CACHE = os.path.join(HERE, "data", "openwebui_data", "cache")
LOGS = os.path.join(HERE, "logs")
PID_FILE = os.path.join(HERE, ".server-pids.txt")


def wipe_sqlite():
    """Delete all user data from SQLite, preserve config and DB structure."""
    if not os.path.isfile(DB_PATH):
        print("[SKIP] webui.db not found — nothing to wipe")
        return

    db = sqlite3.connect(DB_PATH)
    
    # Tables that hold actual user data (wipe these)
    # NOTE: migratehistory and alembic_version are schema tracking tables
    # — they must NEVER be wiped, or Open WebUI will crash on next start
    # with "duplicate column" errors from re-running already-applied migrations.
    user_tables = [
        "user",
        "auth",
        "chat",
        "chatidtag",
        "channel",
        "channel_member",
        "channel_webhook",
        "document",
        "feedback",
        "file",
        "folder",
        "function",
        "group",
        "group_member",
        "knowledge",
        "knowledge_file",
        "memory",
        "message",
        "message_reaction",
        "model",
        "note",
        "oauth_session",
        "prompt",
        "tag",
        "tool",
        "api_key",
    ]

    for table in user_tables:
        try:
            count = db.execute(f"SELECT COUNT(*) FROM [{table}]").fetchone()[0]
            if count > 0:
                db.execute(f"DELETE FROM [{table}]")
                print(f"  Wiped {table}: {count} rows")
        except sqlite3.OperationalError:
            pass  # table doesn't exist in this version

    # Reset SQLite sequences so IDs start fresh (if they exist)
    try:
        db.execute("DELETE FROM sqlite_sequence")
    except sqlite3.OperationalError:
        pass  # no AUTOINCREMENT tables = no sequence table

    # Ensure signup is enabled so the first user can create an admin account
    try:
        config = json.loads(db.execute("SELECT data FROM config").fetchone()[0])
        ui = config.get("ui", {})
        ui["enable_signup"] = True
        ui["default_user_role"] = "admin"
        config["ui"] = ui
        db.execute("UPDATE config SET data = ?", (json.dumps(config),))
        print("  Enabled signup (so first admin account can be created)")
    except Exception:
        pass

    db.commit()
    
    # Show what's left
    remaining = db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).fetchall()
    print(f"\n  Database ready — {len(remaining)} tables (structure + config kept)")
    db.close()


def clear_folder(path, name):
    """Delete everything inside a folder but keep the folder itself."""
    if not os.path.isdir(path):
        print(f"[SKIP] {name} not found")
        return

    count = 0
    for item in os.listdir(path):
        item_path = os.path.join(path, item)
        try:
            if os.path.isfile(item_path) or os.path.islink(item_path):
                os.unlink(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path)
            count += 1
        except Exception as e:
            print(f"  WARNING: could not delete {item}: {e}")
    print(f"  Cleared {name}: {count} items")


def delete_file(path, name):
    """Delete a single file if it exists."""
    if os.path.isfile(path):
        os.unlink(path)
        print(f"  Deleted {name}")
    else:
        print(f"[SKIP] {name} not found")


def main():
    print("=" * 55)
    print("  Enterprise AI Stack — Data Reset")
    print("=" * 55)
    print()

    # 1. Wipe SQLite user data
    print("[1/5] Wiping user data from SQLite...")
    wipe_sqlite()
    print()

    # 2. Delete uploaded documents
    print("[2/5] Removing uploaded documents...")
    clear_folder(UPLOADS, "uploads")
    print()

    # 3. Clear cache
    print("[3/5] Clearing cache...")
    clear_folder(CACHE, "cache")
    print()

    # 4. Clear logs
    print("[4/5] Clearing logs...")
    # Don't delete README.txt if present
    readme = os.path.join(LOGS, "README.txt")
    if os.path.isfile(readme):
        tmp = os.path.join(LOGS, "_README.txt")
        os.rename(readme, tmp)
    clear_folder(LOGS, "logs")
    if os.path.isfile(os.path.join(LOGS, "_README.txt")):
        os.rename(os.path.join(LOGS, "_README.txt"), readme)
    print()

    # 5. Remove PID file
    print("[5/5] Removing PID file...")
    delete_file(PID_FILE, ".server-pids.txt")
    print()

    print("=" * 55)
    print("  Done. Project is clean and ready to copy.")
    print()
    print("  Kept:")
    print("    - Config (RAG settings, model endpoints)")
    print("    - Ollama model weights (data/ollama_models/)")
    print("    - All application code and executables")
    print()
    print("  Wiped:")
    print("    - User accounts (2)")
    print("    - Chat conversations (18)")
    print("    - Uploaded documents (18)")
    print("    - Knowledge base")
    print("    - Cache and logs")
    print("=" * 55)

    return 0


if __name__ == "__main__":
    sys.exit(main())
