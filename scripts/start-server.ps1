<# 
  start-server.ps1
  Enterprise AI Stack -- Server Launcher (PowerShell)
  
  Starts all services with:
    * GPU/CPU auto-detection
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
$ollamaOk = Check-Dependency -Name "ollama.exe" -ExePath "$APPS\ollama\ollama.exe"
$pythonOk = Check-Dependency -Name "python.exe" -ExePath $PYTHON
if (-not $pythonOk -or -not $qdrantOk) {
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
if (-not $HasGPU) {
    Write-Output "  > Running in CPU-ONLY mode. LLM inference will be slower."
    Write-Output "  > This is expected: this server has no NVIDIA GPU."
}
Write-Output ""

# ── Shared Env ─────────────────────────────────────────────
$env:OLLAMA_MODELS = "$DATA\ollama_models"
# Fix Unicode output for Python services (Open WebUI splash screen)
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
            for ($i = 0; $i -lt 30; $i++) {
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
                Write-Output "  [$Name] WARNING: process is running but not responding on port (waited 30s)"
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

# ── 2. Ollama ───────────────────────────────────────────────
if (-not (Test-Path $env:OLLAMA_MODELS)) {
    New-Item -ItemType Directory -Force -Path $env:OLLAMA_MODELS | Out-Null
}
$procs['Ollama'] = Launch-Service -Name "Ollama" `
    -ExePath "$APPS\ollama\ollama.exe" `
    -Arguments @('serve') `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 11434 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 3. Docling Serve ───────────────────────────────────────
$procs['Docling'] = Launch-Service -Name "Docling" `
    -ExePath "$APPS\python_env\Scripts\docling-serve.exe" `
    -Arguments @('run', '--port', '5001') `
    -ExtraEnv @{
        DOCLING_SERVE_ENABLE_UI = "true"
        UVICORN_WORKERS = "1"
    } `
    -HealthCheck { (Test-NetConnection -ComputerName 127.0.0.1 -Port 5001 -WarningAction SilentlyContinue).TcpTestSucceeded }

# ── 4. Open WebUI ──────────────────────────────────────────
$procs['OpenWebUI'] = Launch-Service -Name "OpenWebUI" `
    -ExePath "$APPS\python_env\Scripts\open-webui.exe" `
    -Arguments @('serve') `
    -ExtraEnv @{
        DATA_DIR = "$DATA\openwebui_data"
        OLLAMA_BASE_URL = "http://127.0.0.1:11434"
        RAG_EMBEDDING_ENGINE = "ollama"
        RAG_EMBEDDING_MODEL = "embeddinggemma"
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
Write-Output "  Qdrant    : http://127.0.0.1:6333  (gRPC: 6334)"
Write-Output "  Ollama    : http://127.0.0.1:11434"
Write-Output "  Docling   : http://127.0.0.1:5001/docs"
Write-Output "  Open WebUI: http://127.0.0.1:8080"
Write-Output "  Logs      : $LOGS"
Write-Output "  PIDs      : $PID_FILE"
Write-Output ""
Write-Output "  To stop:   powershell -File scripts\stop-server.ps1"
Write-Output "  Watchdog:  powershell -File scripts\watchdog.ps1"
Write-Output ""
$gpuText = if($HasGPU){'NVIDIA GPU available'}else{'CPU-only mode (slower)'}
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
