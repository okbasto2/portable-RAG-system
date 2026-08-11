#!/usr/bin/env python3
"""
clear-semantic-cache.py — Clear the semantic response cache.

Deletes all cached prompt/response entries from the SQLite database
(data/semantic_cache/cache.db). The config file (threshold, max_entries)
is preserved. The running cache server picks up the change immediately
(it re-reads the DB on the next request via the stats/count path — if the
server is running, its in-memory index is refreshed on restart; the safest
order is: stop server -> clear -> start server, but clearing while running
works too because a fresh match is always checked against SQLite).

Usage:
    apps\\python_env\\python.exe scripts\\clear-semantic-cache.py
"""
import json
import os
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(ROOT, "data", "semantic_cache")
DB_PATH = os.path.join(CACHE_DIR, "cache.db")
CONFIG_PATH = os.path.join(CACHE_DIR, "config.json")

# Optional: keep the in-memory index in sync if the server is running
# by calling its HTTP clear endpoint when reachable.
CACHE_SERVER_URL = os.environ.get("SEMANTIC_CACHE_URL", "http://127.0.0.1:11436")


def clear_via_http():
    """If the cache server is running, ask it to clear (keeps its index in sync)."""
    try:
        import urllib.request

        req = urllib.request.Request(f"{CACHE_SERVER_URL}/v1/cache/clear", method="POST")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            return data.get("cleared", 0)
    except Exception:
        return None


def main():
    n_http = clear_via_http()

    if not os.path.exists(DB_PATH):
        print("No cache database found — nothing to clear.")
        if n_http is not None:
            print(f"(cache server reported {n_http} entries cleared)")
        return

    db = sqlite3.connect(DB_PATH)
    n = db.execute("SELECT COUNT(*) FROM cache").fetchone()[0]
    db.execute("DELETE FROM cache")
    db.commit()
    db.close()

    print(f"Semantic cache cleared: {n} entr(y/ies) removed.")
    print(f"Database: {DB_PATH}")
    if os.path.exists(CONFIG_PATH):
        print(f"Config preserved: {CONFIG_PATH}")
    if n_http is not None and n_http != n:
        print(f"(cache server cleared {n_http} entries via HTTP; DB had {n})")


if __name__ == "__main__":
    main()
