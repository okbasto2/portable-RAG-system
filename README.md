<div align="center">

# ⚡ Enterprise AI Stack — Portable RAG System

**A self-contained, truly portable, offline Enterprise RAG stack with zero system dependencies.**

[![Platform](https://img.shields.io/badge/Platform-Windows%20x64-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Python](https://img.shields.io/badge/Python-3.11%20Embeddable-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Open WebUI](https://img.shields.io/badge/UI-Open%20WebUI-FF6F61?style=for-the-badge)](https://github.com/open-webui/open-webui)
[![llama.cpp](https://img.shields.io/badge/Inference-llama.cpp-9C8CFF?style=for-the-badge)](https://github.com/ggml-org/llama.cpp)
[![Qdrant](https://img.shields.io/badge/VectorDB-Qdrant-DC2626?style=for-the-badge)](https://qdrant.tech)
[![Docling](https://img.shields.io/badge/Parser-Docling-4B5563?style=for-the-badge)](https://github.com/DS4SD/docling)

</div>

---

## 🌟 Overview

The **Enterprise AI Stack** is a production-grade, privacy-first Retrieval-Augmented Generation (RAG) platform packaged as a **truly portable, relocatable Windows bundle**. 

It combines state-of-the-art open-source AI services into a single folder that can run off any drive or USB stick with **zero installation, zero registry modifications, and zero global Python dependencies**.

### Key Highlights

- 🚀 **1-Click Self-Contained Deployment**: Double-click `start-project.bat` to spin up all services automatically (llama.cpp chat, llama.cpp embeddings, Qdrant, Docling, Open WebUI).
- 🔄 **Dynamic Shebang Relocation Engine**: Utilizes a custom Python relocator (`fix-portable.py`) using `distlib`'s `<launcher_dir>` token so entry points resolve `python.exe` anywhere.
- 🛡️ **Self-Healing Watchdog**: Companion monitoring service (`watchdog.ps1`) continuously checks endpoint health and automatically restarts failed services.
- ⚡ **Auto-Hardware Acceleration**: Automatically detects NVIDIA GPUs via `nvidia-smi` and falls back gracefully to multi-core CPU execution.
- 🔒 **Air-Gapped & Private**: Runs 100% locally on your machine with no data leaving your environment.

---

## 🏗️ Architecture & Component Stack

```
                                  ┌────────────────────────┐
                                  │      Open WebUI        │
                                  │  http://127.0.0.1:8080 │
                                  └───────────┬────────────┘
                                              │  chat /v1
                                              ▼
                              ┌────────────────────────────┐
                              │   Semantic Cache Proxy     │
                              │  http://127.0.0.1:11436    │
                              └─────────────┬──────────────┘
                                            │  cache miss → forward
            ┌─────────────────┬───────────────┼───────────────┬─────────────────┐
            │                 │               │               │                 │
            ▼                 ▼               ▼               ▼                 ▼
 ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
 │  llama.cpp (chat) │ │  llama.cpp (emb)  │ │   Qdrant Vector   │ │   Docling Serve   │
 │ http://127.0.0.1  │ │ http://127.0.0.1  │ │ http://127.0.0.1  │ │ http://127.0.0.1  │
 │      :11434/v1    │ │      :11435/v1    │ │       :6333       │ │       :5001       │
 └───────────────────┘ └───────────────────┘ └───────────────────┘ └───────────────────┘
 LLM Inference (GGUF)    Embeddings (GGUF)     Vector Search Engine     PDF & Doc Parser
```

### Integrated Services

| Component | Service | Local Endpoint | Description |
|---|---|---|---|
| **Frontend** | Open WebUI | `http://127.0.0.1:8080` | Feature-rich AI chat interface & RAG management dashboard |
| **Vector DB** | Qdrant | `http://127.0.0.1:6333` | High-performance vector database storing document embeddings |
| **Semantic Cache** | Cache Proxy | `http://127.0.0.1:11436` | SQLite-backed semantic response cache between Open WebUI and llama.cpp (see below) |
| **Inference** | llama.cpp (chat) | `http://127.0.0.1:11434/v1` | OpenAI-compatible LLM server (Qwen3.5-4B GGUF) with automatic GPU/CPU detection |
| **Embeddings** | llama.cpp (embeddings) | `http://127.0.0.1:11435/v1` | OpenAI-compatible embedding server (embeddinggemma-300M GGUF) |
| **Document Processing** | Docling Serve | `http://127.0.0.1:5001/docs` | Enterprise document parser converting PDF/DOCX to structured Markdown |

---

## ⚡ Quick Start

### 📦 1-Click Portable Download

1. **Download Release Assets**:
   Download the latest release files (`portable-rag-system.zip.001` & `portable-rag-system.zip.002`) from [GitHub Releases](../../releases).

2. **Extract the Bundle**:
   - Place both files in the same folder.
   - Right-click `portable-rag-system.zip.001` -> **Extract Here** (using 7-Zip or WinRAR), or run in CMD:
     ```cmd
     copy /b portable-rag-system.zip.001 + portable-rag-system.zip.002 portable-rag-system.zip
     ```

3. **Alternative — Automated Provisioning**:
   Run the setup script in PowerShell. It will automatically create all folder structures, download Portable Python 3.11, Qdrant, llama.cpp (CPU build + CUDA build when an NVIDIA GPU is detected), the GGUF chat & embedding models, install all dependencies, and patch Python launcher shebangs:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/setup-portable.ps1
   ```

4. **Launch the RAG System**:
   Double-click **`start-project.bat`** (or run `.\start-project.bat` in CMD/PowerShell). All services will initialize automatically!

---

## 🔧 Management & Utility Scripts

The project keeps a clean root folder (`start-project.bat` & `stop-project.bat`) while internal management tools are neatly organized inside `scripts/`:

```
├── start-project.bat           # 1-Click Start (runs shebang repair + launches server)
├── stop-project.bat            # 1-Click Stop (graceful shutdown for all services)
├── install-model.bat           # 1-Click Install a chat model from a GGUF link
├── uninstall-model.bat         # 1-Click Remove an installed model
├── README.md                   # Project documentation
├── requirements.txt            # Python dependencies
└── scripts/
    ├── setup-portable.ps1      # Automated environment & binary downloader
    ├── start-server.ps1        # Core PowerShell orchestrator (GPU detection, health checks)
    ├── stop-server.ps1         # Multi-service graceful stopper
    ├── watchdog.ps1            # Active health monitoring & crash auto-recovery service
    ├── fix-portable.py         # Relocates distlib launcher shebangs (#!<launcher_dir>\..\python.exe)
    ├── semantic-cache-server.py# SQLite-backed semantic response cache proxy (:11436)
    ├── clear-semantic-cache.py # Wipe all cached responses (keeps config)
    ├── install-model.ps1       # Chat model installer engine (download + models.ini registration)
    ├── uninstall-model.ps1     # Model uninstaller engine (menu + config reset)
    ├── reset-data.py           # Data reset engine
    ├── diagnose-portable.bat   # System diagnostic tool
    ├── fix-portable.bat        # Manual shebang repair trigger
    ├── reset-project.bat       # Hard data reset wrapper
    └── open-database.bat       # Shortcut for Qdrant Web Dashboard
```

### Launching the Watchdog (Self-Healing Mode)

To enable automatic crash recovery for long-running deployments, start the watchdog companion in a separate terminal:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/watchdog.ps1
```

---

## 🧠 Semantic Caching

A **semantic response cache** sits between Open WebUI and the chat model. Instead of re-generating an answer every time, the cache embeds each question and replays the stored response when a semantically similar prompt has been answered before — dramatically cutting latency for repeated or paraphrased questions.

### How it works

```
Open WebUI ──> :11436 cache proxy ──> llama.cpp chat (:11434)
                    │
                    ├─ embeds the question via embeddinggemma (:11435)
                    ├─ cosine similarity vs. cached prompts (SQLite, on disk)
                    ├─ ≥ threshold?  ──> replay stored response instantly
                    └─ below threshold → forward to llama.cpp, stream live, then store
```

- **Storage is SQLite on disk** (`data/semantic_cache/cache.db`) — not RAM. Only a ~3 MB in-memory index holds prompt embeddings for fast lookup. The cache survives restarts.
- **Streaming preserved**: cache misses stream tokens to the UI in real time (tee) while being buffered for storage — no added latency.
- **RAG-aware**: Open WebUI injects retrieved knowledge-base chunks into the prompt. The proxy strips the RAG wrapper to key on the *pure question*, and fingerprints the `<context>` block — so a cached answer is only replayed when the **same question hits the same knowledge base**. Different KB content always regenerates (never a stale cross-KB answer).
- **LRU eviction**: when the cache reaches `max_entries`, the least-recently-used responses are evicted.
- **Fail-open**: if the embedding server is unreachable, requests pass straight through uncached.

### Configuration (`data/semantic_cache/config.json`)

Hot-reloaded on every request — **no restart needed**:

```json
{
  "threshold": 0.92,
  "max_entries": 1000
}
```

| Key | Default | Meaning |
|---|---|---|
| `threshold` | `0.92` | Minimum cosine similarity (0–1) for a cache hit. Higher = stricter (fewer hits, safer). Typical range **0.90–0.95**; `0.98` ≈ only near-identical prompts hit. |
| `max_entries` | `1000` | Maximum number of cached responses (LRU eviction when exceeded). |

### Usage

- **Watch cache stats** (entries, hits, misses, threshold): `http://127.0.0.1:11436/v1/cache/stats`
- **Clear the cache** (keeps `config.json`):
  ```powershell
  apps\python_env\python.exe scripts\clear-semantic-cache.py
  ```
  The script calls the running server's `/v1/cache/clear` endpoint so the in-memory index stays in sync; if the server is down it wipes the database file directly.

---

## 📦 Installing & Removing Models

The chat server runs in **router mode**: every model registered in `data\llama_models\models.ini` appears in Open WebUI's model picker, and you switch per chat. Models load on demand and swap in/out of VRAM (`--models-max 1`), so the 6 GB GPU holds one at a time — first use of a model takes a few seconds.

### Install a chat model (one command)

Run `install-model.bat` — it prompts for a HuggingFace **GGUF** link — or pass it directly:

```bat
install-model.bat https://huggingface.co/<org>/<repo>/resolve/main/<model>.gguf [alias]
```

The installer:
1. Downloads the `.gguf` into `data\llama_models\` (validates the GGUF magic bytes — a 404/HTML page is rejected; an existing valid file is reused, no re-download)
2. Registers it in `models.ini` under `[alias]` — **that alias is the name shown in Open WebUI** (llama.cpp exposes ids in uppercase, e.g. `QWEN3.5:4B`)
3. Other installed models stay selectable — nothing is replaced
4. Offers to restart the stack so the model appears in the picker

The semantic cache is **per-model**, so switching models never replays another model's answers — no cache clearing needed between benchmark runs.

**GPU fit (6 GB VRAM):** ~4B @ Q4_K_M is fully offloaded; ~7–8B @ Q4 fits with partial offload; larger models fall back to CPU (the no-GPU deployment target runs any model on CPU anyway).

### Remove a model

```bat
uninstall-model.bat
```

Shows a numbered list of installed models with their aliases. Deleting one removes the file and its `models.ini` entry — it disappears from the picker after restart; the others are unaffected.

### Embedding models (careful)

Installing a *different* embedding model (editing `$MODEL_EMBED` and `RAG_EMBEDDING_MODEL`) invalidates existing knowledge-base vectors — different dimensions and semantic space. Delete the Qdrant collection and re-upload documents. The shipped default `embeddinggemma` is 768-dim, matching the default collection.

---

## 🔬 How Portability Works: Shebang Relocation

When standard `pip` installs console scripts into a Python environment, it hardcodes absolute system paths inside `.exe` launcher stubs:

```
❌ Standard Pip Shebang (Fails when moved):
#!C:\Users\Developer\Desktop\enterprise-ai-stack\apps\python_env\python.exe
```

Our custom **`scripts/fix-portable.py`** inspects the binary headers of every executable launcher in `apps/python_env/Scripts/` and rewrites the shebang using `distlib`'s dynamic runtime token:

```
✅ Relocated Shebang (Works Anywhere):
#!<launcher_dir>\..\python.exe
```

This ensures the stack resolves `python.exe` relative to the current folder, allowing the directory to be moved across drive letters or machines without broken paths.

---

## 📁 Repository Structure

```
enterprise-ai-stack/
├── scripts/                 # Internal orchestration & management scripts
├── apps/                    # [Ignored in Git] Binary engines (Python, llama.cpp, Qdrant)
├── data/                    # [Ignored in Git] Storage for models, vectors, & user data
├── logs/                    # System logs per service component
├── snapshots/               # Qdrant vector database snapshots
├── storage/                 # Qdrant Raft consensus & index storage
├── requirements.txt         # Frozen Python dependencies
├── start-project.bat        # 1-Click Start Launcher
├── stop-project.bat         # 1-Click Stop Launcher
├── install-model.bat        # 1-Click Install a chat model (prompts for GGUF link)
├── uninstall-model.bat      # 1-Click Remove an installed model
└── README.md                # Project documentation
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

Developed as an Enterprise RAG Research & Engineering Project.

</div>
