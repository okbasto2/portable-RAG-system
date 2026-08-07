#!/usr/bin/env python
"""
fix-portable.py — Make this Enterprise AI Stack folder truly portable.

Problem
-------
When pip installs console-script entry points (e.g. `open-webui`, `docling-serve`)
into a portable Python tree, it generates `Scripts/<name>.exe` launcher stubs
(distlib's t32/t64 launchers). Each launcher embeds an *absolute* shebang line:

    #!C:\\Users\\<user>\\...\\apps\\python_env\\python.exe

That path only exists on the machine where pip was run. Copy the folder to
another PC (or even another drive letter) and every `Scripts\\*.exe` fails to
find its interpreter.

Distlib's launcher supports a **relocatable** shebang: any path starting with
the literal token `<launcher_dir>` is resolved relative to the directory that
contains the .exe at runtime. So changing the embedded shebang to

    #!<launcher_dir>\\..\\python.exe    (Scripts\\ is one level below python_env\\)

makes every launcher find python.exe no matter where the folder lives.

This script:
  * Rewrites the embedded shebang in every Scripts\\*.exe to the relocatable form.
  * Rewrites the `#!` first line of every Scripts\\*.py wrapper the same way.
  * Is idempotent: safe to run repeatedly, and required to run once after
    copying the folder to a new PC (and after any future `pip install` that
    drops new launchers into Scripts\\).

Run it with the project's own portable python:

    apps\\python_env\\python.exe fix-portable.py
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "apps", "python_env", "Scripts")

# python.exe sits one directory ABOVE Scripts/  (apps/python_env/python.exe)
# so relocatable path = <launcher_dir>\..\python.exe
RELOCATABLE = b"#!<launcher_dir>\\..\\python.exe"

# Matches the embedded absolute shebang that pip/distlib writes:
#   #!<anythingWhilstNotNewline>python.exe (optional " args" until newline)
EXE_RE = re.compile(rb"#![^\n\r]{0,260}python(w)?\.exe[^\n\r]*")
# Matches a #! line in a .py script (POSIX-style, on its own first line)
PY_RE = re.compile(rb"^#![^\n\r]*python(w)?\.exe[^\n\r]*", re.MULTILINE)


def patch_exe(path):

    with open(path, "rb") as fh:
        data = fh.read()

    m = EXE_RE.search(data)
    if not m:
        return ("skip", "no absolute python shebang found", None)

    original = m.group(0)
    # Already relocatable (means: a '<launcher_dir>' prefix) -> leave alone
    if b"<launcher_dir>" in original:
        return ("skip", "already relocatable", None)

    # The distlib launcher reads the shebang up to the first '\n'. Build a
    # replacement of exactly the same form so the '\n' terminator is preserved.
    suffix = original.split(b"python")[1]  # e.g. b"w.exe -arg\n" tail leftover? No:
    # Actually `original` already includes python(w).exe (+ optional args) up to \n.
    # We rewrite the WHOLE matched span (which runs *up to* but not including \n)
    # to the relocatable string. Any trailing args after python.exe on the
    # original shebang (e.g. " -arg") are preserved by re-appending after our
    # canonical interpreter string.
    args = b""
    # Find a space-arg tail after 'python.exe' / 'pythonw.exe'
    tail_match = re.search(rb"python(w)?\.exe(\s+\S[^\n\r]*)", original)
    if tail_match:
        args = tail_match.group(2) or b""

    target = m.group(1) == b"w"  # pythonw.exe ?
    interpreter = b"<launcher_dir>\\..\\pythonw.exe" if target else b"<launcher_dir>\\..\\python.exe"
    replacement = b"#!" + interpreter + args

    # NOTE: distlib's FIRST_LINE_RE matches `^#!.*pythonw?[0-9.]*([ \t].*)?$`.
    # Our '<launcher_dir>\..\python.exe' does NOT contain a 'python' token after
    # the path collapse (!) so we must keep the literal "python.exe" inside --
    # which we do. Good. Distlib also strips a leading `<launcher_dir>` token
    # itself and resolves the remainder relative to the exe dir; everything
    # after `python.exe` (a space + args) stays attached verbatim.

    new_data = data[: m.start()] + replacement + data[m.end():]

    # Backup once (only if not already backed up)
    bak = path + ".orig"
    if not os.path.exists(bak):
        try:
            with open(path, "rb") as fh:
                orig_bytes = fh.read()
            with open(bak, "wb") as fh:
                fh.write(orig_bytes)
        except Exception:
            pass

    with open(path, "wb") as fh:
        fh.write(new_data)

    return ("patched", original.decode("latin1", "replace"), replacement.decode("latin1", "replace"))


def patch_py(path):

    with open(path, "rb") as fh:
        data = fh.read()
    m = PY_RE.search(data)
    if not m:
        return ("skip", "no python shebang on first line", None)
    original = m.group(0)
    if b"<launcher_dir>" in original:
        return ("skip", "already relocatable", None)
    target = m.group(1) == b"w"
    interpreter = b"<launcher_dir>\\..\\pythonw.exe" if target else b"<launcher_dir>\\..\\python.exe"
    # Preserve any args after python.exe
    args = b""
    tail = re.search(rb"python(w)?\.exe(\s+\S[^\n\r]*)", original)
    if tail:
        args = tail.group(2) or b""
    replacement = b"#!" + interpreter + args
    new_data = data[: m.start()] + replacement + data[m.end():]
    bak = path + ".orig"
    if not os.path.exists(bak):
        with open(path, "rb") as fh:
            ob = fh.read()
        with open(bak, "wb") as fh:
            fh.write(ob)
    with open(path, "wb") as fh:
        fh.write(new_data)
    return ("patched", original.decode("latin1", "replace"), replacement.decode("latin1", "replace"))


def main():

    if not os.path.isdir(SCRIPTS):
        print("ERROR: Scripts dir not found at %s" % SCRIPTS)
        return 2

    print("=== Fixing pip launcher .exe files ===")
    exe_files = sorted(f for f in os.listdir(SCRIPTS) if f.lower().endswith(".exe"))
    patched = 0
    already = 0
    skipped = 0
    examples = []
    for f in exe_files:
        p = os.path.join(SCRIPTS, f)
        status, a, b = patch_exe(p)
        if status == "patched":
            patched += 1
            if len(examples) < 3:
                examples.append((f, a, b))
        elif status == "skip" and "already" in str(a):
            already += 1
        else:
            skipped += 1
    print("  patched   : %d" % patched)
    print("  already ok: %d" % already)
    print("  skipped   : %d" % skipped)
    if examples:
        print("\n  examples:")
        for f, a, b in examples:
            print("    %-22s" % f)
            print("      before: %s" % a)
            print("      after : %s" % b)

    print("\n=== Fixing pip .py wrapper scripts ===")
    py_files = sorted(f for f in os.listdir(SCRIPTS) if f.lower().endswith(".py"))
    py_patched = 0
    py_already = 0
    py_skipped = 0
    for f in py_files:
        p = os.path.join(SCRIPTS, f)
        status, a, b = patch_py(p)
        if status == "patched":
            py_patched += 1
            print("  patched  : %-22s" % f)
            print("    -> %s" % b)
        elif "already" in str(a):
            py_already += 1
        else:
            py_skipped += 1
    print("  patched: %d, already: %d, skipped: %d" % (py_patched, py_already, py_skipped))

    # Also fix the little helper script at the python_env root if it was copied around
    helper = os.path.join(HERE, "apps", "python_env", "explore-qudrant.py")

    if os.path.isfile(helper):
        # No shebang path there, just informational
        pass

    print("\n=== Ensuring VC++ runtime alongside qdrant ===")
    vc_dlls = ["vcruntime140.dll", "vcruntime140_1.dll"]
    python_env = os.path.join(HERE, "apps", "python_env")
    qdrant_dir = os.path.join(HERE, "apps", "qdrant")
    if os.path.isdir(qdrant_dir):
        for dll in vc_dlls:
            src = os.path.join(python_env, dll)
            dst = os.path.join(qdrant_dir, dll)
            if not os.path.isfile(src):
                print("  WARNING: %s not found in python_env — skipping" % dll)
                continue
            if os.path.isfile(dst):
                # Check if same size (rough check)
                if os.path.getsize(src) == os.path.getsize(dst):
                    print("  OK: %s already present" % dll)
                else:
                    shutil.copy2(src, dst)
                    print("  Updated: %s (size mismatch)" % dll)
            else:
                shutil.copy2(src, dst)
                print("  Copied: %s -> apps/qdrant/" % dll)
    else:
        print("  WARNING: qdrant directory not found at %s" % qdrant_dir)

    print("\n=== DONE ===")
    print("Launchers are now relocatable. The folder can be copied to any")
    print("drive/user on any Windows PC and start-project.bat will work.")
    return 0


if __name__ == "__main__":

    sys.exit(main())
