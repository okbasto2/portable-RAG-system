<# 
  start-server.ps1
  Enterprise AI Stack -- Server Launcher (PowerShell)
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
        $test = Start-Process -FilePath $ExePath -ArgumentList "--version" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\depcheck.tmp" -RedirectStandardError "$env:TEMP\depcheck.tmp" -ErrorAction SilentlyContinue
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
}
Write-Output ""

# ── Shared Env ─────────────────────────────────────────────
$env:OLLAMA_MODELS = "$DATA\ollama_models"
$env:PYTHONIOENCODING = "utf-8"

# ── Service Start Helper ───────────────────────────────────
$PID_FILE = "$ROOT\.server-pids.txt"
if (Test-Path $PID_FILE) { Remove-Item $PID_FILE -Force }

function Start-ServiceProcess {
    param(
        [string]$Name,
        [string]$ExePath,
        [string]$ArgumentList,
        [string]$LogFile,
        [string]$WorkingDirectory = $ROOT
    )
    Write-Output "Starting $Name..."
    $errLog = "$LogFile.err.log"
    $p = Start-Process -FilePath $ExePath `
                       -ArgumentList $ArgumentList `
                       -WorkingDirectory $WorkingDirectory `
                       -NoNewWindow `
                       -PassThru `
                       -RedirectStandardOutput $LogFile `
                       -RedirectStandardError $errLog
    
    Add-Content -Path $PID_FILE -Value "$Name=$($p.Id)"
    Write-Output "  [OK] $Name PID: $($p.Id)"
    return $p
}

# 1. Qdrant
Start-ServiceProcess -Name "Qdrant" `
                     -ExePath "$APPS\qdrant\qdrant.exe" `
                     -ArgumentList "--uri http://127.0.0.1:6333" `
                     -LogFile "$LOGS\qdrant.log" `
                     -WorkingDirectory "$APPS\qdrant"

# 2. Ollama
Start-ServiceProcess -Name "Ollama" `
                     -ExePath "$APPS\ollama\ollama.exe" `
                     -ArgumentList "serve" `
                     -LogFile "$LOGS\ollama.log" `
                     -WorkingDirectory "$APPS\ollama"

# 3. Docling
$env:DOCLING_SERVE_ENABLE_UI = "true"
Start-ServiceProcess -Name "Docling" `
                     -ExePath "$APPS\python_env\Scripts\docling-serve.exe" `
                     -ArgumentList "run --port 5001" `
                     -LogFile "$LOGS\docling.log"

# 4. Open WebUI
$env:DATA_DIR = "$DATA\openwebui_data"
$env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
$env:QDRANT_URI = "http://127.0.0.1:6333"
$env:DOCLING_SERVE_URL = "http://127.0.0.1:5001"
$env:WEBUI_AUTH = "true"

Start-ServiceProcess -Name "OpenWebUI" `
                     -ExePath "$APPS\python_env\Scripts\open-webui.exe" `
                     -ArgumentList "serve --port 8080" `
                     -LogFile "$LOGS\openwebui.log"

Write-Output ""
Write-Output "All 4 microservices launched successfully!"
Write-Output "Open WebUI: http://127.0.0.1:8080"
