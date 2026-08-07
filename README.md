<div align="center">

# ⚡ Enterprise AI Stack — Portable RAG System

**A self-contained, truly portable, offline Enterprise RAG stack with zero system dependencies.**

[![Platform](https://img.shields.io/badge/Platform-Windows%20x64-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Python](https://img.shields.io/badge/Python-3.11%20Embeddable-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Open WebUI](https://img.shields.io/badge/UI-Open%20WebUI-FF6F61?style=for-the-badge)](https://github.com/open-webui/open-webui)
[![Ollama](https://img.shields.io/badge/Inference-Ollama-000000?style=for-the-badge&logo=ollama&logoColor=white)](https://ollama.com)
[![Qdrant](https://img.shields.io/badge/VectorDB-Qdrant-DC2626?style=for-the-badge)](https://qdrant.tech)
[![Docling](https://img.shields.io/badge/Parser-Docling-4B5563?style=for-the-badge)](https://github.com/DS4SD/docling)

</div>

---

## 🌟 Overview

The **Enterprise AI Stack** is a production-grade, privacy-first Retrieval-Augmented Generation (RAG) platform packaged as a **truly portable, relocatable Windows bundle**. 

It combines state-of-the-art open-source AI services into a single folder that can run off any drive or USB stick with **zero installation, zero registry modifications, and zero global Python dependencies**.

### Key Highlights

- 🚀 **1-Click Self-Contained Deployment**: Double-click `start-project.bat` to spin up all 4 microservices automatically.
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
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         ▼
         ┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
         │      Ollama       │     │   Qdrant Vector   │     │   Docling Serve   │
         │ http://127.0.0.1  │     │ http://127.0.0.1  │     │ http://127.0.0.1  │
         │      :11434       │     │       :6333       │     │       :5001       │
         └───────────────────┘     └───────────────────┘     └───────────────────┘
         Local LLM Inference       Vector Search Engine      PDF & Doc Parser
```

### Integrated Services

| Component | Service | Local Endpoint | Description |
|---|---|---|---|
| **Frontend** | Open WebUI | `http://127.0.0.1:8080` | Feature-rich AI chat interface & RAG management dashboard |
| **Vector DB** | Qdrant | `http://127.0.0.1:6333` | High-performance vector database storing document embeddings |
| **Inference** | Ollama | `http://127.0.0.1:11434` | Local LLM inference engine supporting Llama 3, Mistral, Qwen, etc. |
| **Document Processing** | Docling Serve | `http://127.0.0.1:5001/docs` | Enterprise document parser converting PDF/DOCX to structured Markdown |

---

## ⚡ Quick Start

### 🚀 Automated Setup (Recommended)

1. **Clone the Repository**:
   ```powershell
   git clone https://github.com/okbasto2/portable-RAG-system.git
   cd portable-RAG-system
   ```

2. **Run Automated Provisioning**:
   Run the setup script in PowerShell. It will automatically create all folder structures, download Portable Python 3.11, Qdrant, and Ollama binaries, install all dependencies, and patch Python launcher shebangs:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/setup-portable.ps1
   ```

3. **Launch the Stack**:
   Double-click **`start-project.bat`** (or run `.\start-project.bat` in CMD/PowerShell).

---

### 📦 Alternative: Pre-Packaged 1-Click Zip

If you prefer to download a pre-built offline zip containing all binaries pre-installed:
1. Download `enterprise-ai-stack-portable.zip` from [GitHub Releases](../../releases).
2. Extract the folder anywhere (e.g. `C:\AI-Stack` or a USB Flash Drive).
3. Double-click **`start-project.bat`**.

---

## 🔧 Management & Utility Scripts

The project keeps a clean root folder (`start-project.bat` & `stop-project.bat`) while internal management tools are neatly organized inside `scripts/`:

```
├── start-project.bat           # 1-Click Start (runs shebang repair + launches server)
├── stop-project.bat            # 1-Click Stop (graceful shutdown for all services)
├── README.md                   # Project documentation
├── requirements.txt            # Python dependencies
└── scripts/
    ├── setup-portable.ps1      # Automated environment & binary downloader
    ├── start-server.ps1        # Core PowerShell orchestrator (GPU detection, health checks)
    ├── stop-server.ps1         # Multi-service graceful stopper
    ├── watchdog.ps1            # Active health monitoring & crash auto-recovery service
    ├── fix-portable.py         # Relocates distlib launcher shebangs (#!<launcher_dir>\..\python.exe)
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
├── apps/                    # [Ignored in Git] Binary engines (Python, Ollama, Qdrant)
├── data/                    # [Ignored in Git] Storage for models, vectors, & user data
├── logs/                    # System logs per service component
├── snapshots/               # Qdrant vector database snapshots
├── storage/                 # Qdrant Raft consensus & index storage
├── requirements.txt         # Frozen Python dependencies
├── start-project.bat        # 1-Click Start Launcher
├── stop-project.bat         # 1-Click Stop Launcher
└── README.md                # Project documentation
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

Developed as an Enterprise RAG Research & Engineering Project.

</div>
