#!/usr/bin/env python3
"""
semantic-cache-server.py — Semantic response cache proxy for the portable RAG stack.

Sits between Open WebUI and llama.cpp:
    Open WebUI  ->  :11436 (this proxy)  ->  llama-server chat   :11434/v1
                                   embed via embedding server    :11435/v1

How it works
------------
1. Every POST /v1/chat/completions is inspected: the last user message is
   embedded with the embedding model (embeddinggemma, 768 dims).
2. Cosine similarity is computed against every cached prompt for the same
   model (in-memory numpy index, rebuilt from SQLite at startup).
3. If best similarity >= threshold  ->  the stored response is replayed
   (streaming clients get the original SSE payloads back; non-streaming get JSON).
4. Otherwise the request is forwarded to llama-server, the response is
   buffered, cached (prompt embedding + response) and returned.
5. Cache is capped at `max_entries` (default 1000); LRU eviction by last hit.

Storage is SQLite on disk (data/semantic_cache/cache.db) — NOT RAM. Only the
~3 MB embedding index is held in memory for fast similarity lookup.

Config (data/semantic_cache/config.json, hot-reloaded every request):
    { "threshold": 0.92, "max_entries": 1000 }
    - threshold:   minimum cosine similarity (0..1) for a cache hit.
                   Higher = stricter (fewer hits). 0.90-0.95 typical.
    - max_entries: maximum number of cached responses (LRU eviction).

Endpoints
---------
    POST /v1/chat/completions   cached/passthrough chat
    GET  /v1/cache/stats        cache statistics (entries, hits, threshold)
    POST /v1/cache/clear        clear the cache (JSON {"cleared": N})
    everything else             transparent proxy to llama-server

Run:  apps\\python_env\\python.exe scripts\\semantic-cache-server.py
"""
import asyncio
import json
import os
import sqlite3
import time

import numpy as np
from aiohttp import web, ClientSession, ClientTimeout

# ── Paths / constants ────────────────────────────────────────────────────
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(ROOT, "data", "semantic_cache")
DB_PATH = os.path.join(CACHE_DIR, "cache.db")
CONFIG_PATH = os.path.join(CACHE_DIR, "config.json")

CHAT_UPSTREAM = os.environ.get("LLAMA_CHAT_URL", "http://127.0.0.1:11434/v1")
EMBED_UPSTREAM = os.environ.get("LLAMA_EMBED_URL", "http://127.0.0.1:11435/v1")
HOST = "127.0.0.1"
PORT = int(os.environ.get("SEMANTIC_CACHE_PORT", "11436"))
EMBED_MODEL = os.environ.get("SEMANTIC_CACHE_EMBED_MODEL", "embeddinggemma")

DEFAULT_CONFIG = {"threshold": 0.92, "max_entries": 1000}
CONFIG_CACHE = {"threshold": 0.92, "max_entries": 1000, "_mtime": 0}


def load_config(force=False):
    """Hot-reload config.json. Falls back to defaults on any error."""
    try:
        mtime = os.path.getmtime(CONFIG_PATH)
        if force or mtime != CONFIG_CACHE["_mtime"]:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            CONFIG_CACHE["threshold"] = float(cfg.get("threshold", DEFAULT_CONFIG["threshold"]))
            CONFIG_CACHE["max_entries"] = int(cfg.get("max_entries", DEFAULT_CONFIG["max_entries"]))
            CONFIG_CACHE["_mtime"] = mtime
    except Exception:
        if CONFIG_CACHE["_mtime"] == 0:
            CONFIG_CACHE["threshold"] = DEFAULT_CONFIG["threshold"]
            CONFIG_CACHE["max_entries"] = DEFAULT_CONFIG["max_entries"]
    return CONFIG_CACHE


# ── SQLite store (disk) ──────────────────────────────────────────────────
_db = None
_db_lock = asyncio.Lock()


def get_db():
    global _db
    if _db is None:
        os.makedirs(CACHE_DIR, exist_ok=True)
        _db = sqlite3.connect(DB_PATH, check_same_thread=False)
        _db.execute(
            """
            CREATE TABLE IF NOT EXISTS cache (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                model         TEXT    NOT NULL,
                prompt        TEXT    NOT NULL,
                context_hash  TEXT    NOT NULL DEFAULT '',
                embedding     BLOB    NOT NULL,      -- float32[768], L2-normalized
                response_json TEXT    NOT NULL,      -- assembled OpenAI completion
                response_sse  TEXT    NOT NULL,      -- JSON list of SSE payload dicts
                created_at    REAL    NOT NULL,
                last_hit_at   REAL    NOT NULL,
                hit_count     INTEGER NOT NULL DEFAULT 1
            )
            """
        )
        try:
            # migration for older DBs (pre context_hash)
            _db.execute("ALTER TABLE cache ADD COLUMN context_hash TEXT NOT NULL DEFAULT ''")
            _db.commit()
        except sqlite3.OperationalError:
            pass  # column already exists
        _db.execute("CREATE INDEX IF NOT EXISTS idx_cache_model ON cache(model)")
        _db.commit()
    return _db


# ── In-memory similarity index (mirrors SQLite; rebuilt at startup) ──────
index = {}
context_hashes = {}   # row_id -> context fingerprint ('' = plain chat, no RAG)
hits_total = 0
misses_total = 0


def rebuild_index():
    global index, context_hashes
    index = {}
    context_hashes = {}
    db = get_db()
    rows = db.execute("SELECT id, model, context_hash, embedding FROM cache").fetchall()
    for row_id, model, ctx_hash, blob in rows:
        vec = np.frombuffer(blob, dtype=np.float32)
        data = index.setdefault(model, {"ids": [], "vecs": []})
        data["ids"].append(row_id)
        data["vecs"].append(vec)
        context_hashes[row_id] = ctx_hash
    for model, data in index.items():
        data["ids"] = np.array(data["ids"], dtype=np.int64)
        data["vecs"] = np.vstack(data["vecs"]) if data["vecs"] else np.zeros((0, 768), dtype=np.float32)
    total = sum(len(d["ids"]) for d in index.values())
    print(f"[cache] index rebuilt: {total} cached prompt(s)")


def find_best_match(model, query_vec, context_hash=""):
    """Return (row_id, similarity) for the closest cached prompt with the SAME
    context fingerprint, or (None, 0). Context fingerprinting keeps RAG answers
    isolated: a cached answer generated against knowledge base A is never
    replayed for the same question against knowledge base B."""
    data = index.get(model)
    if data is None or len(data["ids"]) == 0:
        return None, 0.0
    sims = data["vecs"] @ query_vec          # cosine (both normalized)
    best_i, best_sim = -1, 0.0
    for i in np.argsort(sims)[::-1]:         # best first
        row_id = int(data["ids"][i])
        if context_hashes.get(row_id, "") == context_hash:
            best_i, best_sim = i, float(sims[i])
            break
    if best_i < 0 or best_sim < load_config()["threshold"]:
        return None, best_sim
    return int(data["ids"][best_i]), best_sim


def add_entry(model, prompt, context_hash, embedding, response_json, response_sse):
    db = get_db()
    now = time.time()
    cur = db.execute(
        "INSERT INTO cache (model, prompt, context_hash, embedding, response_json, response_sse, created_at, last_hit_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (model, prompt, context_hash, embedding.tobytes(), json.dumps(response_json),
         json.dumps(response_sse), now, now),
    )
    db.commit()
    row_id = cur.lastrowid
    context_hashes[row_id] = context_hash
    # update in-memory index
    data = index.setdefault(model, {"ids": np.array([], dtype=np.int64),
                                    "vecs": np.zeros((0, 768), dtype=np.float32)})
    data["ids"] = np.append(data["ids"], row_id)
    data["vecs"] = np.vstack([data["vecs"], embedding.reshape(1, -1)])

    # LRU eviction (per model, keeps total <= max_entries)
    max_entries = load_config()["max_entries"]
    if len(data["ids"]) > max_entries:
        rows = db.execute(
            "SELECT id FROM cache WHERE model=? ORDER BY last_hit_at ASC LIMIT ?",
            (model, len(data["ids"]) - max_entries),
        ).fetchall()
        victim_ids = [r[0] for r in rows]
        for vid in victim_ids:
            db.execute("DELETE FROM cache WHERE id=?", (vid,))
            context_hashes.pop(vid, None)
        db.commit()
        remaining = db.execute("SELECT id, context_hash, embedding FROM cache WHERE model=?", (model,)).fetchall()
        index[model] = {
            "ids": np.array([r[0] for r in remaining], dtype=np.int64),
            "vecs": np.vstack([np.frombuffer(r[2], dtype=np.float32) for r in remaining])
                    if remaining else np.zeros((0, 768), dtype=np.float32),
        }
        for r in remaining:
            context_hashes[r[0]] = r[1]
        print(f"[cache] evicted {len(victim_ids)} entry(ies); {len(remaining)} remain for '{model}'")
    return row_id


def get_entry(row_id):
    db = get_db()
    row = db.execute(
        "SELECT model, prompt, response_json, response_sse, hit_count FROM cache WHERE id=?",
        (row_id,),
    ).fetchone()
    if not row:
        return None
    now = time.time()
    db.execute("UPDATE cache SET last_hit_at=?, hit_count=? WHERE id=?",
               (now, row[4] + 1, row_id))
    db.commit()
    return {"model": row[0], "prompt": row[1],
            "response_json": json.loads(row[2]),
            "response_sse": json.loads(row[3]),
            "hit_count": row[4] + 1}


# ── Embedding via llama.cpp embedding server ─────────────────────────────
async def embed_prompt(session, text):
    """Returns L2-normalized float32 vector or None on failure."""
    try:
        payload = {"model": EMBED_MODEL, "input": text}
        async with session.post(f"{EMBED_UPSTREAM}/embeddings", json=payload) as resp:
            if resp.status != 200:
                return None
            data = await resp.json()
            vec = np.array(data["data"][0]["embedding"], dtype=np.float32)
            norm = np.linalg.norm(vec)
            if norm > 0:
                vec = vec / norm
            return vec
    except Exception as e:
        print(f"[cache] embedding failed (bypassing cache): {e}")
        return None


import hashlib


def extract_query_and_context(messages):
    """From the last user message, return (pure_query, context_fingerprint).

    Open WebUI's RAG flow REPLACES the user message with the rendered template:
        ### Task: ... <context>...chunks...</context> <query>the question</query>
    (rag_template + add_or_update_user_message in open_webui/utils). The real
    question is everything after the closing </context> tag; the context block
    is fingerprinted so cache hits never cross knowledge bases.

    Plain (non-RAG) chats have no context tag -> fingerprint ''.
    """
    for msg in reversed(messages or []):
        if msg.get("role") == "user":
            content = msg.get("content", "")
            if isinstance(content, list):
                parts = [p.get("text", "") for p in content
                         if isinstance(p, dict) and p.get("type") == "text"]
                content = "\n".join(parts)
            if not isinstance(content, str):
                return None, ""
            marker = "</context>"
            idx = content.rfind(marker)
            if idx != -1:
                query = content[idx + len(marker):].strip()
                if query:
                    ctx_block = content[:idx + len(marker)]
                    fingerprint = hashlib.sha256(ctx_block.encode("utf-8")).hexdigest()[:32]
                    return query, fingerprint
            return content, ""  # no RAG wrapper — plain chat
    return None, ""


def assemble_response(payloads):
    """Merge streaming SSE payload dicts (or a single non-stream JSON)
    into one OpenAI completion JSON."""
    # Non-streaming: upstream returned a complete JSON object already
    if len(payloads) == 1 and "choices" in payloads[0]:
        p = payloads[0]
        choices = p.get("choices") or []
        if choices and "message" in choices[0] and not choices[0].get("delta"):
            return p

    msg = {"role": "assistant", "content": "", "reasoning_content": ""}
    finish = None
    usage = None
    resp_id, model, created = None, None, None
    for p in payloads:
        choices = p.get("choices") or []
        if not choices:
            continue
        c = choices[0]
        if resp_id is None:
            resp_id, model, created = p.get("id"), p.get("model"), p.get("created")
        delta = c.get("delta", {})
        if delta.get("role"):
            msg["role"] = delta["role"]
        if delta.get("content"):
            msg["content"] += delta["content"]
        if delta.get("reasoning_content"):
            msg["reasoning_content"] += delta["reasoning_content"]
        if c.get("finish_reason"):
            finish = c["finish_reason"]
        if p.get("usage"):
            usage = p["usage"]
    if not msg.get("reasoning_content"):
        msg.pop("reasoning_content", None)
    return {
        "id": resp_id or "chatcmpl-cache",
        "object": "chat.completion",
        "created": created or int(time.time()),
        "model": model or "",
        "choices": [{"index": 0, "message": msg, "finish_reason": finish or "stop"}],
        "usage": usage or {},
    }


# ── SSE streaming helpers ────────────────────────────────────────────────
async def stream_payloads(request, payloads):
    """Replay stored/forwarded SSE payloads to the client.
    Client disconnects mid-stream (tab closed, generation stopped) are normal —
    swallow them so they don't spam the log with tracebacks."""
    resp = web.StreamResponse(
        status=200,
        headers={"Content-Type": "text/event-stream",
                 "Cache-Control": "no-cache",
                 "Connection": "keep-alive"},
    )
    try:
        await resp.prepare(request)
        for p in payloads:
            await resp.write(f"data: {json.dumps(p)}\n\n".encode())
        await resp.write(b"data: [DONE]\n\n")
        await resp.write_eof()
    except (ConnectionResetError, asyncio.CancelledError, RuntimeError):
        # client went away mid-stream; nothing more to send
        pass
    except Exception as e:
        print(f"[cache] stream error (client may have disconnected): {e}")
    return resp


async def replay_response(request, entry, want_stream):
    if want_stream:
        return await stream_payloads(request, entry["response_sse"])
    return web.json_response(entry["response_json"])


# ── Upstream forwarding ──────────────────────────────────────────────────
async def forward_and_buffer(session, body):
    """POST to llama-server. Returns (parsed SSE payloads, ok)."""
    want_stream = bool(body.get("stream", False))
    timeout = ClientTimeout(total=600)
    payloads = []
    try:
        async with session.post(f"{CHAT_UPSTREAM}/chat/completions", json=body,
                                timeout=timeout) as resp:
            if resp.status != 200:
                text = await resp.text()
                print(f"[cache] upstream error {resp.status}: {text[:200]}")
                return [], False
            if want_stream:
                async for line in resp.content:
                    line = line.strip()
                    if not line.startswith(b"data:"):
                        continue
                    data = line[5:].strip()
                    if data == b"[DONE]":
                        break
                    try:
                        payloads.append(json.loads(data))
                    except json.JSONDecodeError:
                        continue
            else:
                payloads.append(await resp.json())
        return payloads, True
    except Exception as e:
        print(f"[cache] upstream error: {e}")
        return [], False


async def forward_stream_tee(session, request, body):
    """Forward a streaming request to llama-server, relaying SSE chunks to the
    client in real time (live tokens) while collecting them for the cache.
    Returns (payloads, response, ok)."""
    timeout = ClientTimeout(total=600)
    payloads = []
    resp = web.StreamResponse(
        status=200,
        headers={"Content-Type": "text/event-stream",
                 "Cache-Control": "no-cache",
                 "Connection": "keep-alive"},
    )
    try:
        async with session.post(f"{CHAT_UPSTREAM}/chat/completions", json=body,
                                timeout=timeout) as upstream:
            if upstream.status != 200:
                text = await upstream.text()
                print(f"[cache] upstream error {upstream.status}: {text[:200]}")
                return [], None, False
            await resp.prepare(request)
            async for line in upstream.content:
                line = line.strip()
                if not line:
                    continue
                # relay to the client immediately (live streaming)
                try:
                    await resp.write(line + b"\n\n")
                except (ConnectionResetError, asyncio.CancelledError, RuntimeError):
                    pass  # client went away; keep reading to populate the cache
                if not line.startswith(b"data:"):
                    continue
                data = line[5:].strip()
                if data == b"[DONE]":
                    break
                try:
                    payloads.append(json.loads(data))
                except json.JSONDecodeError:
                    continue
            await resp.write_eof()
        return payloads, resp, True
    except Exception as e:
        print(f"[cache] upstream error: {e}")
        return [], None, False


async def proxy_chat_passthrough(session, request, body):
    """Raw passthrough when the request can't be cached."""
    timeout = ClientTimeout(total=600)
    async with session.post(f"{CHAT_UPSTREAM}/chat/completions", json=body,
                            timeout=timeout) as resp:
        raw = await resp.read()
        ctype = resp.headers.get("Content-Type", "application/json").split(";")[0].strip()
        return web.Response(body=raw, status=resp.status, content_type=ctype, charset=resp.charset)


async def proxy_all(request):
    """Generic transparent proxy for every other path/method."""
    session = get_session(request)
    # CHAT_UPSTREAM already ends with /v1, so strip the leading /v1 from the
    # incoming path to avoid /v1/v1/... double-prefixing (e.g. /v1/models).
    path = request.path
    if path.startswith("/v1/"):
        path = path[len("/v1"):]
    target = f"{CHAT_UPSTREAM}{path}"
    headers = {k: v for k, v in request.headers.items()
               if k.lower() not in ("host", "content-length")}
    timeout = ClientTimeout(total=600)
    body = await request.read()
    async with session.request(request.method, target, data=body,
                               headers=headers, timeout=timeout) as resp:
        raw = await resp.read()
        # aiohttp's content_type must not carry charset — pass it separately
        ctype = resp.headers.get("Content-Type", "application/json").split(";")[0].strip()
        charset = resp.charset
        return web.Response(body=raw, status=resp.status, content_type=ctype, charset=charset)


# ── Chat completion handler ──────────────────────────────────────────────
async def handle_chat(request):
    global hits_total, misses_total
    session = get_session(request)
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    model = body.get("model", "")
    messages = body.get("messages", [])
    want_stream = bool(body.get("stream", False))
    prompt, ctx_fp = extract_query_and_context(messages)

    if not prompt or not model:
        return await proxy_chat_passthrough(session, request, body)

    query_vec = await embed_prompt(session, prompt)
    if query_vec is None:
        return await proxy_chat_passthrough(session, request, body)

    row_id, sim = find_best_match(model, query_vec, ctx_fp)

    if row_id is not None:
        hits_total += 1
        entry = get_entry(row_id)
        print(f"[cache] HIT  sim={sim:.3f} model={model} ctx={ctx_fp[:8] or 'plain'} hits={entry['hit_count']}")
        return await replay_response(request, entry, want_stream)

    misses_total += 1
    print(f"[cache] MISS sim={sim:.3f} model={model} ctx={ctx_fp[:8] or 'plain'} (threshold={load_config()['threshold']})")

    if want_stream:
        # Live streaming passthrough: relay chunks as they arrive, tee into cache.
        payloads, stream_resp, ok = await forward_stream_tee(session, request, body)
        if not ok:
            return web.json_response({"error": "upstream error"}, status=502)
        if payloads:
            resp_json = assemble_response(payloads)
            content = resp_json["choices"][0]["message"].get("content", "")
            if content.strip():
                async with _db_lock:
                    add_entry(model, prompt, ctx_fp, query_vec, resp_json, payloads)
                print(f"[cache] stored response for model={model}")
        return stream_resp

    payloads, ok = await forward_and_buffer(session, body)
    if not ok:
        # upstream failed — pass through raw error if we have nothing
        if not payloads:
            return web.json_response({"error": "upstream error"}, status=502)
        return web.json_response(payloads[-1], status=502)

    resp_json = assemble_response(payloads)
    content = resp_json["choices"][0]["message"].get("content", "")
    if content.strip():
        async with _db_lock:
            add_entry(model, prompt, ctx_fp, query_vec, resp_json, payloads)
        print(f"[cache] stored response for model={model}")

    return web.json_response(resp_json)


# ── Stats / clear endpoints ──────────────────────────────────────────────
async def handle_stats(request):
    db = get_db()
    n = db.execute("SELECT COUNT(*) FROM cache").fetchone()[0]
    cfg = load_config()
    return web.json_response({
        "entries": n,
        "max_entries": cfg["max_entries"],
        "threshold": cfg["threshold"],
        "hits_total": hits_total,
        "misses_total": misses_total,
        "db_path": DB_PATH,
        "config_path": CONFIG_PATH,
    })


async def handle_clear(request):
    global index, context_hashes
    db = get_db()
    async with _db_lock:
        n = db.execute("SELECT COUNT(*) FROM cache").fetchone()[0]
        db.execute("DELETE FROM cache")
        db.commit()
    index = {}
    context_hashes = {}
    print(f"[cache] cleared {n} entry(ies)")
    return web.json_response({"cleared": n})


# ── App wiring ───────────────────────────────────────────────────────────
async def on_startup(app):
    app["session"] = ClientSession(timeout=ClientTimeout(total=600))


async def on_cleanup(app):
    session = app.get("session")
    if session:
        await session.close()


def get_session(request):
    return request.app["session"]


async def make_app():
    app = web.Application()
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    app.router.add_post("/v1/chat/completions", handle_chat)
    app.router.add_get("/v1/cache/stats", handle_stats)
    app.router.add_post("/v1/cache/clear", handle_clear)
    app.router.add_route("*", "/{tail:.*}", proxy_all)
    return app


def main():
    if not os.path.exists(CONFIG_PATH):
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_CONFIG, f, indent=2)
        print(f"[cache] wrote default config: {CONFIG_PATH}")

    load_config(force=True)
    get_db()
    rebuild_index()

    print(f"[cache] semantic cache proxy on http://{HOST}:{PORT}")
    print(f"[cache] chat upstream   : {CHAT_UPSTREAM}")
    print(f"[cache] embed upstream  : {EMBED_UPSTREAM}")
    print(f"[cache] threshold       : {CONFIG_CACHE['threshold']}")
    print(f"[cache] max_entries     : {CONFIG_CACHE['max_entries']}")
    print(f"[cache] db              : {DB_PATH}")

    app = asyncio.run(make_app())
    web.run_app(app, host=HOST, port=PORT, print=None)


if __name__ == "__main__":
    main()
