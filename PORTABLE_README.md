# Enterprise AI Stack — Portable

A self-contained, **truly portable** bundle of:
- **Ollama** (`apps/ollama/`) — LLM inference engine
- **Qdrant** (`apps/qdrant/`) — vector database
- **Portable Python 3.11** (`apps/python_env/`) — embeddable Python with
  **Open WebUI**, **Docling Serve**, and their dependencies pre-installed

No system-wide installs, no venv, no environment variables set outside the
project. Copy the folder to **any** drive/user on **any** Windows PC and
double-click `start-project.bat`.

---

## Quick start

1. Copy this entire folder (`enterprise-ai-stack/`) anywhere, e.g.
   `C:\Users\<You>\Desktop\enterprise-ai-stack\` or a USB stick.
2. Double-click **`start-project.bat`**.

The first run automatically fixes any pip-launcher paths so they resolve to
*this* folder's `python.exe`, then launches all services:

| Service     | URL                       |
|-------------|---------------------------|
| Open WebUI  | http://127.0.0.1:8080     |
| Qdrant      | http://127.0.0.1:6333      |
| Ollama API  | http://127.0.0.1:11434    |
| Docling UI  | http://127.0.0.1:5001/docs|

To shut everything down, double-click **`stop-project.bat`**.

---

## Why a "fix" step was needed

When `pip` installs console scripts (like `open-webui`, `docling-serve`) it
generates `apps/python_env/Scripts/<name>.exe` launchers. Each launcher is a
tiny stub that embeds an **absolute** shebang pointing at the `python.exe`
that existed when pip ran:

```
#!C:\Users\okbaDesktop\Desktop\enterprise-ai-stack\apps\python_env\python.exe
```

That path is **machine-specific**. On a different PC (or even a different
drive letter on the same PC) every `Scripts\*.exe` fails with
*"Failed to create process"* and the whole stack won't start.

### The fix — relocatable shebangs

Distlib's launcher (the stub pip uses) supports a special token,
**`<launcher_dir>`**, which it resolves **at runtime** relative to the
directory that contains the `.exe`. The embedded shebang in every launcher
has been rewritten to:

```
#!<launcher_dir>\..\python.exe
```

(`Scripts\` is one level below `python_env\`, hence `..\`.) This makes every
launcher find `python.exe` next to itself, wherever the folder lives.

This is distlib's **documented** mechanism for relocatable launchers, not a
hack — see <https://distlib.readthedocs.io/en/latest/tutorial.html>.

### Files in this repo that implement it

| File              | Purpose                                                       |
|-------------------|---------------------------------------------------------------|
| `fix-portable.py` | Python tool that rewrites every `Scripts/*.exe` and `*.py`  |
|                   | shebang to the `<launcher_dir>` form. Idempotent.            |
| `fix-portable.bat`| One-click wrapper that runs `fix-portable.py` with the       |
|                   | in-tree portable python. Run this manually if needed.        |
| `start-project.bat`| Launcher; auto-runs the fixer on first start (writes a      |
|                   | `.portable-fixed` marker so it only runs once), then starts  |
|                   | Qdrant, Ollama, Docling, Open WebUI.                          |
| `stop-project.bat`| Stops all services by image name. Already fully portable.    |

---

## When to re-run `fix-portable.bat`

- **Not normally** — `start-project.bat` already does it once per new location.
- **After you `pip install` a new package** that adds new `Scripts\*.exe`
  launchers (those new launchers will carry absolute paths again). Just run
  `fix-portable.bat` and they're made relocatable too.
- **After copying the folder to a new PC** — unneeded if `start-project.bat`
  is used (it self-fixes), but harmless and quick.

`fix-portable.py` is idempotent: running it twice does nothing the second
time, and it preserves `.orig` backups of every file it touches under
`Scripts\*.exe.orig`.

---

## Layout

```
enterprise-ai-stack/
├─ apps/
│  ├─ ollama/              ollama.exe + lib/        (LLM engine)
│  ├─ qdrant/             qdrant.exe              (vector DB)
│  └─ python_env/         embeddable Python 3.11
│     ├─ python.exe
│     ├─ python311._pth   (relative paths — already portable)
│     ├─ Lib/site-packages/  open_webui, docling, qdrant_client, …
│     └─ Scripts/         *.exe launchers (relocatable shebangs)
├─ data/
│  ├─ ollama_models/      models live here (OLLAMA_MODELS)
│  ├─ qdrant_storage/     Qdrant data
│  ├─ openwebui_data/     Open WebUI data
│  └─ n8n_data/           (optional) n8n data
├─ storage/               Qdrant raft state + collections
├─ snapshots/
├─ start-project.bat      ← double-click to run
├─ stop-project.bat       ← double-click to stop
├─ fix-portable.bat       ← re-fix launchers after pip install / move
├─ fix-portable.py        (the actual relocator; called by the .bat files)
├─ .webui_secret_key
├─ .portable-fixed        (auto-created on first start; safe to delete)
└─ PORTABLE_README.md     (this file)
```

---

## Notes

- **No system Python / no venv is used.** Everything runs from
  `apps/python_env/python.exe`, which uses `python311._pth` with relative
  entries (`.` and `Lib\site-packages`) — already portable, no changes needed.
- **Ollama model storage** is redirected inside the project via the
  `OLLAMA_MODELS` env var set in `start-project.bat` (relative `%DATA_DIR%`).
- **Qdrant** runs with no config file (in-memory defaults + `storage/` for
  raft state) — portable.
- **Open WebUI secrets** (`DATA_DIR`, `OLLAMA_BASE_URL`, `QDRANT_URI`, …) are
  all set from `%~dp0`-derived relative paths in `start-project.bat`. No
  machine-specific values anywhere.
