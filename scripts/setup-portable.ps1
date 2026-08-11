<# 
  setup-portable.ps1
  Enterprise AI Stack -- Automated Setup Script
#>

$ErrorActionPreference = "Stop"
# Force TLS 1.2 (Windows PowerShell 5.1 defaults to TLS 1.0 which modern servers reject)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path -Parent $SCRIPT_DIR
Set-Location $ROOT

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Enterprise AI Stack -- Automated Setup" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Create Folder Hierarchy ─────────────────────────────
Write-Host "[1/6] Creating project folder structure..." -ForegroundColor Yellow

$dirs = @(
    "$ROOT\apps\python_env",
    "$ROOT\apps\qdrant",
    "$ROOT\apps\llamacpp\cpu",
    "$ROOT\apps\llamacpp\cuda",
    "$ROOT\data\llama_models",
    "$ROOT\data\qdrant_storage",
    "$ROOT\data\openwebui_data",
    "$ROOT\data\n8n_data",
    "$ROOT\storage",
    "$ROOT\logs",
    "$ROOT\snapshots"
)

foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}
Write-Host "  [OK] Directory hierarchy created." -ForegroundColor Green

# ── 2. Download & Extract Portable Python 3.11 ──────────────
$pythonExe = "$ROOT\apps\python_env\python.exe"
if (-not (Test-Path $pythonExe)) {
    Write-Host "[2/6] Downloading Portable Python 3.11..." -ForegroundColor Yellow
    $pyZip = "$env:TEMP\python-embed-3.11.9.zip"
    $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
    
    Invoke-WebRequest -Uri $pyUrl -OutFile $pyZip -UseBasicParsing
    Expand-Archive -Path $pyZip -DestinationPath "$ROOT\apps\python_env" -Force
    Remove-Item $pyZip -ErrorAction SilentlyContinue

    # Enable site-packages in python311._pth
    $pth = "$ROOT\apps\python_env\python311._pth"
    if (Test-Path $pth) {
        $content = Get-Content $pth
        $content = $content -replace '#import site', 'import site'
        Set-Content -Path $pth -Value $content
    }
    Write-Host "  [OK] Portable Python 3.11 installed." -ForegroundColor Green
} else {
    Write-Host "[2/6] Portable Python 3.11 already present." -ForegroundColor Green
}

# ── 3. Install Pip & Requirements ──────────────────────────
$pipExe = "$ROOT\apps\python_env\Scripts\pip.exe"
if (Test-Path "$ROOT\requirements.txt") {
    Write-Host "[3/6] Installing Python dependencies (this may take a few minutes)..." -ForegroundColor Yellow
    if (-not (Test-Path $pipExe)) {
        $getPip = "$env:TEMP\get-pip.py"
        # Try GitHub mirror first (more reliable on restricted networks), fallback to official
        $pipUrls = @(
            "https://github.com/pypa/get-pip/raw/main/public/get-pip.py",
            "https://bootstrap.pypa.net/get-pip.py"
        )
        $downloaded = $false
        foreach ($url in $pipUrls) {
            try {
                Write-Host "  Downloading get-pip.py from $url ..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $url -OutFile $getPip -UseBasicParsing -TimeoutSec 15
                $downloaded = $true
                break
            } catch {
                Write-Host "  [WARN] Failed: $url" -ForegroundColor Yellow
            }
        }
        if (-not $downloaded) {
            Write-Host "  [ERROR] Could not download get-pip.py from any source." -ForegroundColor Red
            exit 1
        }
        & $pythonExe $getPip --no-warn-script-location
        Remove-Item $getPip -ErrorAction SilentlyContinue
    }
    & $pythonExe -m pip install -r "$ROOT\requirements.txt" --no-warn-script-location
    Write-Host "  [OK] Python dependencies installed." -ForegroundColor Green
} else {
    Write-Host "[3/6] WARNING: requirements.txt not found. Skipping pip install." -ForegroundColor Red
}

# ── 4. Download Qdrant Vector DB ────────────────────────────
$qdrantExe = "$ROOT\apps\qdrant\qdrant.exe"
if (-not (Test-Path $qdrantExe)) {
    Write-Host "[4/6] Downloading Qdrant Vector Database..." -ForegroundColor Yellow
    $qdrantZip = "$env:TEMP\qdrant.zip"
    $qdrantUrl = "https://github.com/qdrant/qdrant/releases/download/v1.12.1/qdrant-x86_64-pc-windows-msvc.zip"
    
    Invoke-WebRequest -Uri $qdrantUrl -OutFile $qdrantZip -UseBasicParsing
    Expand-Archive -Path $qdrantZip -DestinationPath "$ROOT\apps\qdrant" -Force
    Remove-Item $qdrantZip -ErrorAction SilentlyContinue
    Write-Host "  [OK] Qdrant installed." -ForegroundColor Green
} else {
    Write-Host "[4/6] Qdrant already present." -ForegroundColor Green
}

# ── 5. Download llama.cpp LLM Engine + GGUF Models ─────────
$llamaServer = "$ROOT\apps\llamacpp\cpu\llama-server.exe"
if (-not (Test-Path $llamaServer)) {
    Write-Host "[5/6] Downloading llama.cpp (CPU build)..."
    $llamaZip = "$env:TEMP\llamacpp-cpu.zip"
    $llamaUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b10333/llama-b10333-bin-win-cpu-x64.zip"

    Invoke-WebRequest -Uri $llamaUrl -OutFile $llamaZip -UseBasicParsing
    Expand-Archive -Path $llamaZip -DestinationPath "$ROOT\apps\llamacpp\cpu" -Force
    Remove-Item $llamaZip -ErrorAction SilentlyContinue
    Write-Host "  [OK] llama.cpp CPU build installed." -ForegroundColor Green
} else {
    Write-Host "[5/6] llama.cpp CPU build already present." -ForegroundColor Green
}

# Optional CUDA build — only when an NVIDIA GPU is detected
$hasGpu = $false
try {
    $null = & nvidia-smi 2>$null
    if ($LASTEXITCODE -eq 0) { $hasGpu = $true }
} catch { }
if ($hasGpu -and -not (Test-Path "$ROOT\apps\llamacpp\cuda\llama-server.exe")) {
    Write-Host "  [i] NVIDIA GPU detected - downloading CUDA build for acceleration..." -ForegroundColor Yellow
    $cudaZip = "$env:TEMP\llamacpp-cuda.zip"
    $cudaUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b10333/llama-b10333-bin-win-cuda-12.4-x64.zip"

    Invoke-WebRequest -Uri $cudaUrl -OutFile $cudaZip -UseBasicParsing
    Expand-Archive -Path $cudaZip -DestinationPath "$ROOT\apps\llamacpp\cuda" -Force
    Remove-Item $cudaZip -ErrorAction SilentlyContinue
    Write-Host "  [OK] llama.cpp CUDA build installed." -ForegroundColor Green
}

# GGUF chat model (Qwen3.5-4B Q4_K_M, ~2.6 GB)
$chatModel = "$ROOT\data\llama_models\Qwen3.5-4B-Q4_K_M.gguf"
if (-not (Test-Path $chatModel)) {
    Write-Host "  [i] Downloading chat model Qwen3.5-4B-Q4_K_M.gguf (~2.6 GB)..."
    Invoke-WebRequest -Uri "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf" -OutFile $chatModel -UseBasicParsing
    Write-Host "  [OK] Chat model downloaded." -ForegroundColor Green
} else {
    Write-Host "  [i] Chat model already present." -ForegroundColor Green
}

# GGUF embedding model (embeddinggemma-300M Q8_0, ~318 MB)
$embedModel = "$ROOT\data\llama_models\embeddinggemma-300M-Q8_0.gguf"
if (-not (Test-Path $embedModel)) {
    Write-Host "  [i] Downloading embedding model embeddinggemma-300M-Q8_0.gguf (~318 MB)..."
    Invoke-WebRequest -Uri "https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf" -OutFile $embedModel -UseBasicParsing
    Write-Host "  [OK] Embedding model downloaded." -ForegroundColor Green
} else {
    Write-Host "  [i] Embedding model already present." -ForegroundColor Green
}

# ── 6. Fix Relocatable Shebangs ────────────────────────────
Write-Host "[6/6] Patching Python script shebangs for portability..." -ForegroundColor Yellow
$fixerScript = "$SCRIPT_DIR\fix-portable.py"
if (Test-Path $fixerScript) {
    & $pythonExe $fixerScript
    Write-Host "  [OK] Shebang relocation complete." -ForegroundColor Green
} else {
    Write-Host "  [WARN] fix-portable.py not found at $fixerScript" -ForegroundColor Red
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete! You can now run start-project.bat" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
