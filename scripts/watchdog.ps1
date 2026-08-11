<# 
  watchdog.ps1
  Enterprise AI Stack -- Crash Recovery Watchdog
#>

param(
    [switch]$Once,
    [int]$CheckInterval = 10
)

$ErrorActionPreference = "Continue"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path -Parent $SCRIPT_DIR
$LOGS = "$ROOT\logs"
$PID_FILE = "$ROOT\.server-pids.txt"
$WATCHDOG_LOG = "$LOGS\watchdog-$(Get-Date -Format 'yyyyMMdd').log"

New-Item -ItemType Directory -Force -Path $LOGS | Out-Null

function Write-Log($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $msg"
    Write-Output $line
    $line | Out-File -FilePath $WATCHDOG_LOG -Append -Encoding UTF8
}

$APPS  = "$ROOT\apps"
$DATA  = "$ROOT\data"

# ── GPU-aware llama.cpp build selection (mirrors start-server.ps1) ──
$HasGPU = $false
try {
    $nvidia = & nvidia-smi 2>$null
    if ($LASTEXITCODE -eq 0) { $HasGPU = $true }
} catch { }

if ($HasGPU -and (Test-Path "$APPS\llamacpp\cuda\llama-server.exe")) {
    $LLAMA_SERVER = "$APPS\llamacpp\cuda\llama-server.exe"
    $NGL = "99"
} else {
    $LLAMA_SERVER = "$APPS\llamacpp\cpu\llama-server.exe"
    $NGL = "0"
}

$services = @{
    "Qdrant" = @{
        Exe       = "$APPS\qdrant\qdrant.exe"
        Args      = @('--uri', 'http://127.0.0.1:6333')
        Port      = 6333
        WorkDir   = "$APPS\qdrant"
        Env       = @{}
    }
    "LlamaChat" = @{
        Exe       = $LLAMA_SERVER
        Args      = @('-m', "$DATA\llama_models\Qwen3.5-4B-Q4_K_M.gguf", '--host', '127.0.0.1', '--port', '11434', '--alias', 'qwen3.5:4b', '-c', '8192', '-ngl', $NGL, '--reasoning', 'off', '--no-webui')
        Port      = 11434
        WorkDir   = "$APPS\llamacpp"
        Env       = @{}
    }
    "LlamaEmbed" = @{
        Exe       = $LLAMA_SERVER
        Args      = @('-m', "$DATA\llama_models\embeddinggemma-300M-Q8_0.gguf", '--host', '127.0.0.1', '--port', '11435', '--alias', 'embeddinggemma', '--embeddings', '--pooling', 'mean', '-c', '2048', '-ngl', $NGL, '--no-webui')
        Port      = 11435
        WorkDir   = "$APPS\llamacpp"
        Env       = @{}
    }
    "Docling" = @{
        Exe       = "$APPS\python_env\Scripts\docling-serve.exe"
        Args      = @('run', '--port', '5001')
        Port      = 5001
        WorkDir   = "$ROOT"
        Env       = @{ DOCLING_SERVE_ENABLE_UI = "true" }
    }
    "OpenWebUI" = @{
        Exe       = "$APPS\python_env\Scripts\open-webui.exe"
        Args      = @('serve', '--port', '8080')
        Port      = 8080
        WorkDir   = "$ROOT"
        Env       = @{
            DATA_DIR         = "$DATA\openwebui_data"
            ENABLE_OLLAMA_API = "false"
            OPENAI_API_BASE_URL = "http://127.0.0.1:11434/v1"
            OPENAI_API_KEY   = "llama.cpp"
            RAG_EMBEDDING_ENGINE = "openai"
            RAG_EMBEDDING_MODEL = "embeddinggemma"
            RAG_OPENAI_API_BASE_URL = "http://127.0.0.1:11435/v1"
            RAG_OPENAI_API_KEY = "llama.cpp"
            QDRANT_URI       = "http://127.0.0.1:6333"
            DOCLING_SERVE_URL= "http://127.0.0.1:5001"
            WEBUI_AUTH       = "true"
        }
    }
}

function Test-ServiceHealth($port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar = $tcp.BeginConnect("127.0.0.1", $port, $null, $null)
        $wait = $ar.AsyncWaitHandle.WaitOne(2000, $false)
        if (-not $wait) {
            $tcp.Close()
            return $false
        }
        $tcp.EndConnect($ar)
        $tcp.Close()
        return $true
    } catch {
        return $false
    }
}

Write-Log "Watchdog started (Check interval: ${CheckInterval}s, llama.cpp build: $(Split-Path -Parent $LLAMA_SERVER))"

do {
    foreach ($svcName in $services.Keys) {
        $svc = $services[$svcName]
        $alive = Test-ServiceHealth -port $svc.Port
        
        if (-not $alive) {
            Write-Log "CRITICAL: $svcName (port $($svc.Port)) is DOWN! Attempting restart..."
            
            $logFile = "$LOGS\${svcName}-crash.log"
            
            foreach ($k in $svc.Env.Keys) {
                [Environment]::SetEnvironmentVariable($k, $svc.Env[$k], "Process")
            }
            
            try {
                $p = Start-Process -FilePath $svc.Exe `
                                   -ArgumentList ($svc.Args -join ' ') `
                                   -WorkingDirectory $svc.WorkDir `
                                   -NoNewWindow `
                                   -PassThru `
                                   -RedirectStandardOutput $logFile `
                                   -RedirectStandardError $logFile
                
                Write-Log "RESTARTED: $svcName with new PID $($p.Id)"
            } catch {
                Write-Log "ERROR: Failed to restart $svcName : $_"
            }
        }
    }
    
    if (-not $Once) {
        Start-Sleep -Seconds $CheckInterval
    }
} while (-not $Once)
