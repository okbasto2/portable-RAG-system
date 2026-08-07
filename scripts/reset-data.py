#!/usr/bin/env python
"""
reset-data.py — Wipe all user data, keep config and models.
"""
import json
import os
import shutil
import sqlite3
import sys

# Since this script sits in scripts/, project root is 1 directory level up:
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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
            pass

    try:
        db.execute("DELETE FROM sqlite_sequence")
    except sqlite3.OperationalError:
        pass

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
    db.execute("VACUUM")
    db.close()
    print("[OK] SQLite database reset successfully")


def wipe_folders():
    """Delete uploaded files, caches, and logs."""
    for label, path in [("uploads", UPLOADS), ("cache", CACHE), ("logs", LOGS)]:
        if os.path.isdir(path):
            try:
                shutil.rmtree(path)
                os.makedirs(path, exist_ok=True)
                print(f"[OK] Cleared {label} ({path})")
            except Exception as e:
                print(f"[WARN] Failed to clear {label}: {e}")
        else:
            os.makedirs(path, exist_ok=True)

    if os.path.isfile(PID_FILE):
        try:
            os.remove(PID_FILE)
            print("[OK] Removed PID file")
        except Exception:
            pass


def main():
    print("===================================================")
    print("  Enterprise AI Stack — Resetting User Data")
    print("===================================================")
    print(f"Root: {HERE}")
    print("")

    wipe_sqlite()
    wipe_folders()

    print("")
    print("Reset complete. The project is clean and ready for a new deployment.")


if __name__ == "__main__":
    main()
