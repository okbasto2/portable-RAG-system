<# 
  start-server.ps1
  Enterprise AI Stack -- Server Launcher (PowerShell)
  
  Starts all services with:
    * GPU/CPU auto-detection (llama.cpp picks CUDA build + full offload when GPU present)
    * PID tracking for clean shutdown
    * Startup health checks (wait for each port)
    * Crash recovery via watchdog companion
    
  Run directly:  powershell -ExecutionPolicy Bypass -File scripts\start-server.ps1
  Or via the .bat wrapper: start-project.bat
#>
param(
    [switch]$NoHealthCheck
)

$ErrorActionPreference = "Stop"
# Script is located in scripts/, root is 1 directory level up:
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path -Parent $SCRIPT_DIR
Set-Location $ROOT

$APPS  = "$ROOT\apps"
$DATA  = "$ROOT\data"
$LOGS  = "$ROOT\logs"
$PYTHON = "$APPS\python_env\python.exe"

# ── llama.cpp layout ──────────────────────────────────
$LLAMA_CPU = "$APPS\llamacpp\cpu"
$LLAMA_CUDA = "$APPS\llamacpp\cuda"
$MODEL_CHAT = "$DATA\llama_models\Qwen3.5-4B-Q4_K_M.gguf"
$MODEL_EMBED = "$DATA\llama_models\embeddinggemma-300M-Q8_0.gguf"

# Ensure log directory exists
New-Item -ItemType Directory -Force -Path $LOGS | Out-Null

Write-Output "===================================================="
Write-Output "  Enterprise AI Stack -- Server Launcher"
Write-Output "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "===================================================="
Write-Output "Root  : $ROOT"
Write-Output "Logs  : $LOGS"
Write-Output ""

# ── Pre-flight Dependency Checks ──────────────────────────
function Check-Dependency {
    param([string]$Name, [string]$ExePath)
    if (-not (Test-Path $ExePath)) {
        Write-Output "[PREFLIGHT] WARNING: $Name not found at: $ExePath"
        return $false
    }
    try {
        $tmpOut = "$env:TEMP\depcheck_out.tmp"
        $tmpErr = "$env:TEMP\depcheck_err.tmp"
        $test = Start-Process -FilePath $ExePath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction SilentlyContinue
        if ($null -ne $test -and $test.ExitCode -eq -1073741515) {
            Write-Output "[PREFLIGHT] ERROR: $Name is missing a required DLL (error 0xC0000135)"
            Write-Output "            This means Visual C++ Redistributable is not installed."
            Write-Output "            Fix: install VC++ Redist from https://aka.ms/vs/17/release/vc_redist.x64.exe"
            Write-Output "            OR copy vcruntime140.dll to the same folder as $Name"
            return $false
        }
    } catch {
        Write-Output "  [WARN] $Name - could not test (may still work)"
        return $true
    }
    Write-Output "  [OK] $Name"
    return $true
}

Write-Output "Checking dependencies..."
$qdrantOk = Check-Dependency -Name "qdrant.exe" -ExePath "$APPS\qdrant\qdrant.exe"
$pythonOk = Check-Dependency -Name "python.exe" -ExePath $PYTHON

# Detect which llama.cpp build to use
$llamaDir = $null
if (Test-Path "$LLAMA_CUDA\llama-server.exe") { $llamaDir = $LLAMA_CUDA }
elseif (Test-Path "$LLAMA_CPU\llama-server.exe") { $llamaDir = $LLAMA_CPU }
if ($llamaDir) {
    $llamaOk = Check-Dependency -Name "llama-server.exe" -ExePath "$llamaDir\llama-server.exe"
} else {
    $llamaOk = $false
    Write-Output "[PREFLIGHT] WARNING: llama-server.exe not found in apps\llamacpp\cpu or apps\llamacpp\cuda"
}

foreach ($m in @($MODEL_CHAT, $MODEL_EMBED)) {
    if (-not (Test-Path $m)) {
        Write-Output "[PREFLIGHT] WARNING: model not found: $m"
        Write-Output "            Run scripts\setup-portable.ps1 to download the GGUF models."
    }
}

if (-not $pythonOk -or -not $qdrantOk -or -not $llamaOk) {
    Write-Output "[PREFLIGHT] One or more dependencies are missing. Startup may fail."
}
if (-not (Test-Path "$APPS\python_env\Scripts\docling-serve.exe") -or
    -not (Test-Path "$APPS\python_env\Scripts\open-webui.exe")) {
    Write-Output "[PREFLIGHT] WARNING: Python service launchers not found. Run setup-portable.ps1 first."
}
Write-Output ""

# ── GPU Detection ──────────────────────────────────────────
$HasGPU = $false
try {
    $nvidia = & nvidia-smi 2>$null
    if ($LASTEXITCODE -eq 0) { $HasGPU = $true }
} catch { }
Write-Output "GPU detected: $HasGPU"
if ($HasGPU -and $llamaDir -eq $LLAMA_CUDA) {
    Write-Output "  > Using CUDA build of llama.cpp with full GPU offload (-ngl 99)."
} elseif ($HasGPU) {
    Write-Output "  > GPU present but only the CPU build is installed."
    Write-Output "  > Run scripts\setup-portable.ps1 to install the CUDA build for acceleration."
} else {
    Write-Output "  > Running in CPU-ONLY mode. LLM inference will be slower."
    Write-Output "  > This is expected: this server has no NVIDIA GPU."
}
Write-Output ""

# Determine llama-server binary + offload flags
if ($HasGPU -and (Test-Path "$LLAMA_CUDA\llama-server.exe")) {
    $LLAMA_SERVER = "$LLAMA_CUDA\llama-server.exe"
    $NGL = "99"          # offload all layers to GPU
} else {
    $LLAMA_SERVER = "$LLAMA_CPU\llama-server.exe"
    $NGL = "0"           # pure CPU
}
Write-Output "llama-server : $LLAMA_SERVER"
Write-Output ""

# ── Shared Env ─────────────────────────────────────────────
$env:PYTHONIOENCODING = "utf-8"

# ── PID tracking ───────────────────────────────────────────
$PID_FILE = "$ROOT\.server-pids.txt"
"" | Out-File -FilePath $PID_FILE -Encoding ASCII  # truncate

function Launch-Service {
    param(
        [string]$Name,
        [string]$ExePath,
        [string[]]$Arguments,
        [string]$LogName = $Name.ToLower(),
        [scriptblock]$HealthCheck,
        [hashtable]$ExtraEnv = @{}
    )
    
    Write-Output "[$Name] Starting..."
    
    try {
        # Set any extra environment variables for this service
        foreach ($kv in $ExtraEnv.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
        }
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath
        $psi.Arguments = $Arguments -join " "
        $psi.WorkingDirectory = Split-Path -Parent $ExePath
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $proc = [System.Diagnostics.Process]::Start($psi)
        
        # Write PID to tracking file
        "$Name=$($proc.Id)" | Out-File -FilePath $PID_FILE -Encoding ASCII -Append
        
        Write-Output "  PID=$($proc.Id)"
        
        # Give the process a moment to bind its port
        Start-Sleep -Seconds 2
        
        # Health Check
        if ($HealthCheck -and -not $NoHealthCheck) {
            Write-Output "  [$Name] Waiting for readiness..."
            $ready = $false
            for ($i = 0; $i -lt 60; $i++) {
                Start-Sleep -Seconds 1
                # Show progress dot every 3 seconds so user knows it's not frozen
                if ($i -gt 0 -and $i % 3 -eq 0) {
                    Write-Host -NoNewline "."
                }
                # Check if process already died
                $stillAlive = $false
                try { $p = Get-Process -Id $proc.Id -ErrorAction Stop; $stillAlive = -not $p.HasExited } catch { }
                if (-not $stillAlive) {
                    Write-Host ""  # end the dot line
                    $exitCode = $proc.ExitCode
                    Write-Output "  [$Name] FAILED: process exited immediately (exit code: $exitCode)"
                    if ($exitCode -eq -1073741515 -or $exitCode -eq 3221225781) {
                        Write-Output "  [$Name] HINT: Missing DLL (error 0xC0000135). Install Visual C++ Redistributable."
                    }
                    break
                }
                try { if (& $HealthCheck) { $ready = $true; break } } catch { }
            }
            if ($ready) {
                Write-Host ""  # end the dot line
                Write-Output "  [$Name] READY"
            } elseif ($stillAlive) {
                Write-Host ""  # end the dot line
                Write-Output "  [$Name] WARNING: process is running but not responding on port (waited 60s)"
            }
        }
        
        return $proc
    } catch {
        Write-Output "  [$Name] FAILED: $_"
        return $null
    }
}

$procs = @{}

# ── 1. Qdrant ──────────────────────────────────────────────
if (-not (Test-Path "$DATA\qdrant_storage")) {
    New-Item -ItemType Directory -Force -Path "$DATA\qdrant_storage" | Out-Null
}
$procs['Qdrant'] = Launch-Service -Name "Qdrant" `
    -ExePath "$APPS\qdrant\qdrant.exe" `
    -Arguments @('--uri', 'http://127.0.0.1:6333') `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 6333 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 2. llama.cpp -- Chat (OpenAI-compatible API) ───────────
$procs['LlamaChat'] = Launch-Service -Name "LlamaChat" `
    -ExePath $LLAMA_SERVER `
    -Arguments @(
        '-m', $MODEL_CHAT,
        '--host', '127.0.0.1',
        '--port', '11434',
        '--alias', 'qwen3.5:4b',
        '-c', '8192',
        '-ngl', $NGL,
        '--reasoning', 'off',      # default: no thinking (Open WebUI toggle can re-enable per-request)
        '--no-webui'
    ) `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 11434 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 3. llama.cpp -- Embeddings (OpenAI-compatible API) ─────
$procs['LlamaEmbed'] = Launch-Service -Name "LlamaEmbed" `
    -ExePath $LLAMA_SERVER `
    -Arguments @(
        '-m', $MODEL_EMBED,
        '--host', '127.0.0.1',
        '--port', '11435',
        '--alias', 'embeddinggemma',
        '--embeddings',
        '--pooling', 'mean',
        '-c', '2048',
        '-ngl', $NGL,
        '--no-webui'
    ) `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 11435 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 4. Semantic Cache Proxy (Open WebUI <-> llama.cpp) ───────
$procs['SemanticCache'] = Launch-Service -Name "SemanticCache" `
    -ExePath $PYTHON `
    -Arguments @("$SCRIPT_DIR\semantic-cache-server.py") `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 11436 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 5. Docling Serve ───────────────────────────────────────
$procs['Docling'] = Launch-Service -Name "Docling" `
    -ExePath "$APPS\python_env\Scripts\docling-serve.exe" `
    -Arguments @('run', '--port', '5001') `
    -ExtraEnv @{
        DOCLING_SERVE_ENABLE_UI = "true"
        UVICORN_WORKERS = "1"
    } `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 5001 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 6. Open WebUI ──────────────────────────────────────────
$procs['OpenWebUI'] = Launch-Service -Name "OpenWebUI" `
    -ExePath "$APPS\python_env\Scripts\open-webui.exe" `
    -Arguments @('serve') `
    -ExtraEnv @{
        DATA_DIR = "$DATA\openwebui_data"
        # llama.cpp exposes an OpenAI-compatible API; disable the dead Ollama tab
        ENABLE_OLLAMA_API = "false"
        # Chat goes through the semantic cache proxy (:11436) which forwards to llama-server
        OPENAI_API_BASE_URL = "http://127.0.0.1:11436/v1"
        OPENAI_API_KEY = "llama.cpp"
        # RAG embeddings via llama.cpp embedding server (direct, not cached)
        RAG_EMBEDDING_ENGINE = "openai"
        RAG_EMBEDDING_MODEL = "embeddinggemma"
        RAG_OPENAI_API_BASE_URL = "http://127.0.0.1:11435/v1"
        RAG_OPENAI_API_KEY = "llama.cpp"
        VECTOR_DB = "qdrant"
        QDRANT_URI = "http://127.0.0.1:6333"
        ENABLE_VERSION_UPDATE_CHECK="false"
    } `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 8080 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── Summary ─────────────────────────────────────────────────
Write-Output ""
Write-Output "===================================================="
Write-Output "  Server Stack Running"
Write-Output "===================================================="
Write-Output "  Qdrant      : http://127.0.0.1:6333  (gRPC: 6334)"
Write-Output "  llama.cpp   : http://127.0.0.1:11434/v1  (chat, OpenAI-compatible)"
Write-Output "  llama.cpp   : http://127.0.0.1:11435/v1  (embeddings, OpenAI-compatible)"
Write-Output "  SemanticCache: http://127.0.0.1:11436  (chat cache proxy; /v1/cache/stats)"
Write-Output "  Docling     : http://127.0.0.1:5001/docs"
Write-Output "  Open WebUI  : http://127.0.0.1:8080"
Write-Output "  Logs        : $LOGS"
Write-Output "  PIDs        : $PID_FILE"
Write-Output ""
Write-Output "  To stop:   powershell -File scripts\stop-server.ps1"
Write-Output "  Watchdog:  powershell -File scripts\watchdog.ps1"
Write-Output ""
$gpuText = if($HasGPU -and $LLAMA_SERVER -eq "$LLAMA_CUDA\llama-server.exe"){'NVIDIA GPU (CUDA offload)'}elseif($HasGPU){'NVIDIA GPU (CPU build installed)'}else{'CPU-only mode (slower)'}
Write-Output "  GPU       : $gpuText"
Write-Output "===================================================="

Write-Output ""
Write-Output "Server running. Press Ctrl+C to stop (or close this window)."
Write-Output "To keep it running in background, minimize this window."
Write-Output ""

# Wait for all processes
try {
    while ($procs.Values | Where-Object { -not $_.HasExited }) {
        Start-Sleep -Seconds 5
    }
} finally {
    Write-Output ""
    Write-Output "One or more services have stopped. Run stop-server.ps1 to clean up."
}
