#!/usr/bin/env python
"""
fix-portable.py — Make this Enterprise AI Stack folder truly portable.

Fixes embedded absolute shebangs in Scripts/*.exe and Scripts/*.py
so that Python launchers resolve relative to python_env using <launcher_dir>.
"""
import os
import re
import shutil
import sys

# Since this script sits in scripts/, project root is 1 directory level up:
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(HERE, "apps", "python_env", "Scripts")

RELOCATABLE = b"#!<launcher_dir>\\..\\python.exe"

EXE_RE = re.compile(rb"#![^\n\r]{0,260}python(w)?\.exe[^\n\r]*")
PY_RE = re.compile(rb"^#![^\n\r]*python(w)?\.exe[^\n\r]*", re.MULTILINE)


def patch_exe(path):
    with open(path, "rb") as fh:
        data = fh.read()

    m = EXE_RE.search(data)
    if not m:
        return ("skip", "no absolute python shebang found", None)

    original = m.group(0)
    if b"<launcher_dir>" in original:
        return ("skip", "already relocatable", None)

    args = b""
    tail_match = re.search(rb"python(w)?\.exe(\s+\S[^\n\r]*)", original)
    if tail_match:
        args = tail_match.group(2) or b""

    target = m.group(1) == b"w"
    interpreter = b"<launcher_dir>\\..\\pythonw.exe" if target else b"<launcher_dir>\\..\\python.exe"
    replacement = b"#!" + interpreter + args

    new_data = data[: m.start()] + replacement + data[m.end():]

    bak = path + ".orig"
    if not os.path.exists(bak):
        try:
            with open(path, "rb") as fh:
                shutil.copyfile(path, bak)
        except OSError as e:
            print(f"  [WARN] Backup error for {os.path.basename(path)}: {e}")

    with open(path, "wb") as fh:
        fh.write(new_data)

    return ("patched", original.decode("latin1", "replace"), replacement.decode("latin1", "replace"))


def patch_py(path):
    with open(path, "rb") as fh:
        data = fh.read()

    m = PY_RE.search(data)
    if not m:
        return ("skip", "no python shebang", None)

    original = m.group(0)
    if b"<launcher_dir>" in original:
        return ("skip", "already relocatable", None)

    target = m.group(1) == b"w"
    interpreter = b"<launcher_dir>\\..\\pythonw.exe" if target else b"<launcher_dir>\\..\\python.exe"

    new_data = PY_RE.sub(b"#!" + interpreter, data, count=1)

    with open(path, "wb") as fh:
        fh.write(new_data)

    return ("patched", original.decode("latin1", "replace"), interpreter.decode("latin1", "replace"))


# ── Open WebUI "Think" toggle bridge for llama.cpp ─────────────────────
# Open WebUI's chat UI sends the Ollama-style "think" param for reasoning
# models, but llama.cpp's OpenAI-compatible API only honors
# chat_template_kwargs.enable_thinking. This patch translates the toggle
# so the UI's Think On/Off switch actually controls reasoning.
THINK_MARKER_START = b"# === hermes-llamacpp-think-toggle ==="
THINK_MARKER_END = b"# === end hermes-llamacpp-think-toggle ==="
THINK_PATCH = b"""    # === hermes-llamacpp-think-toggle ===
    # Translate Open WebUI's "think" toggle (Ollama-style param) into
    # llama.cpp's chat_template_kwargs.enable_thinking so the UI toggle
    # actually controls reasoning on OpenAI-compatible backends.
    # Values: null (default) -> not set (server default applies),
    #         true  -> enable_thinking=true  (thinking ON),
    #         false -> enable_thinking=false (thinking OFF).
    _req_params = payload.get("params")
    if isinstance(_req_params, dict) and _req_params.get("think") is not None:
        _ctk = payload.get("chat_template_kwargs") or {}
        _ctk["enable_thinking"] = bool(_req_params["think"])
        payload["chat_template_kwargs"] = _ctk
        _req_params.pop("think", None)
    # === end hermes-llamacpp-think-toggle ===

"""


def patch_openai_think_toggle():
    target = os.path.join(
        HERE, "apps", "python_env", "Lib", "site-packages", "open_webui", "routers", "openai.py"
    )
    if not os.path.exists(target):
        return ("skip", "openai.py not found (open-webui not installed yet)")

    with open(target, "rb") as fh:
        data = fh.read()

    if THINK_MARKER_START in data:
        return ("skip", "think toggle bridge already applied")

    anchor = b"    payload = {**form_data}\n    metadata = payload.pop(\"metadata\", None)\n"
    if anchor not in data:
        return ("error", "anchor line not found in openai.py - manual patch needed")

    new_data = data.replace(anchor, anchor + THINK_PATCH, 1)

    with open(target, "wb") as fh:
        fh.write(new_data)

    return ("patched", "think toggle bridge inserted into openai.py")


def main():
    print(f"Project root : {HERE}")
    print(f"Scripts dir  : {SCRIPTS}")

    if not os.path.isdir(SCRIPTS):
        print(f"[ERROR] Scripts directory not found at: {SCRIPTS}")
        sys.exit(1)

    patched = 0
    skipped = 0

    for name in os.listdir(SCRIPTS):
        full = os.path.join(SCRIPTS, name)
        if not os.path.isfile(full):
            continue

        ext = os.path.splitext(name)[1].lower()

        if ext == ".exe":
            status, orig, new = patch_exe(full)
            if status == "patched":
                patched += 1
                print(f"  [PATCHED EXE] {name}")
            else:
                skipped += 1
        elif ext == ".py":
            status, orig, new = patch_py(full)
            if status == "patched":
                patched += 1
                print(f"  [PATCHED PY]  {name}")
            else:
                skipped += 1

    # Open WebUI think-toggle bridge (llama.cpp OpenAI-compatible API)
    status, detail = patch_openai_think_toggle()
    if status == "patched":
        patched += 1
        print(f"  [PATCHED OPENAI] {detail}")
    else:
        skipped += 1
        print(f"  [SKIP OPENAI] {detail}")

    print("")
    print(f"Done. Patched {patched} launcher(s); {skipped} already relocatable or unmodified.")


if __name__ == "__main__":
    main()
