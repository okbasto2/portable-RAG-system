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

    print("")
    print(f"Done. Patched {patched} launcher(s); {skipped} already relocatable or unmodified.")


if __name__ == "__main__":
    main()
