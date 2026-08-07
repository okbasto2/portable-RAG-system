<# 
  watchdog.ps1
  Enterprise AI Stack -- Crash Recovery Watchdog
  
  Monitors the server processes. If any service dies unexpectedly,
  it restarts it and logs the event.
  
  Run this in a separate terminal after start-server.ps1:
    powershell -ExecutionPolicy Bypass -File watchdog.ps1
  
  Or run it as a Windows scheduled task that fires every minute:
    powershell -ExecutionPolicy Bypass -File watchdog.ps1 -Once
#>

param(
    [switch]$Once,                 # Run once then exit (for scheduled tasks)
    [int]$CheckInterval = 10       # Seconds between checks
)

$ErrorActionPreference = "Continue"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
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

# ── Service definitions (for restart) ──────────────────────
$APPS  = "$ROOT\apps"
$DATA  = "$ROOT\data"

$services = @{
    "Qdrant" = @{
        Exe       = "$APPS\qdrant\qdrant.exe"
        Args      = @('--uri', 'http://127.0.0.1:6333')
        Port      = 6333
        WorkDir   = "$APPS\qdrant"
        Env       = @{}
    }
    "Ollama" = @{
        Exe       = "$APPS\ollama\ollama.exe"
        Args      = @('serve')
        Port      = 11434
        WorkDir   = "$APPS\ollama"
        Env       = @{ OLLAMA_MODELS = "$DATA\ollama_models" }
    }
    "Docling" = @{
        Exe       = "$APPS\python_env\Scripts\docling-serve.exe"
        Args      = @('run', '--port', '5001')
        Port      = 5001
        WorkDir   = "$ROOT"
        Env       = @{
            DOCLING_SERVE_ENABLE_UI = "true"
            UVICORN_WORKERS = "1"
        }
    }
    "OpenWebUI" = @{
        Exe       = "$APPS\python_env\Scripts\open-webui.exe"
        Args      = @('serve')
        Port      = 8080
        WorkDir   = "$ROOT"
        Env       = @{
            DATA_DIR = "$DATA\openwebui_data"
            OLLAMA_BASE_URL = "http://127.0.0.1:11434"
            RAG_EMBEDDING_ENGINE = "ollama"
            RAG_EMBEDDING_MODEL = "embeddinggemma"
            VECTOR_DB = "qdrant"
            QDRANT_URI = "http://127.0.0.1:6333"
        }
    }
}

function Get-TrackedPIDs {
    if (-not (Test-Path $PID_FILE)) { return @{} }
    $result = @{}
    Get-Content $PID_FILE | Where-Object { $_ -match '^(.+)=(\d+)$' } | ForEach-Object {
        $result[$matches[1]] = [int]$matches[2]
    }
    return $result
}

function Test-ProcessAlive($pid) {
    try { $p = Get-Process -Id $pid -ErrorAction Stop; return -not $p.HasExited }
    catch { return $false }
}

function Restart-Service($name, $cfg) {
    Write-Log "RESTARTING $name..."
    
    try {
        $logFile = "$LOGS\$($name.ToLower())-$(Get-Date -Format 'yyyyMMdd').log"
        
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cfg.Exe
        $psi.Arguments = $cfg.Args -join " "
        $psi.WorkingDirectory = $cfg.WorkDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        foreach ($kv in $cfg.Env.GetEnumerator()) {
            $psi.Environment[$kv.Key] = $kv.Value
        }
        
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        
        $allPids = Get-TrackedPIDs
        $allPids[$name] = $proc.Id
        "" | Out-File -FilePath $PID_FILE -Encoding ASCII
        $allPids.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" | Out-File -FilePath $PID_FILE -Append -Encoding ASCII }
        
        Write-Log "  $name restarted -- new PID: $($proc.Id)"
        return $proc.Id
    } catch {
        Write-Log "  FAILED to restart $name : $_"
        return 0
    }
}

# ── Main loop ──────────────────────────────────────────────
Write-Log "Watchdog started (interval: ${CheckInterval}s)"
Write-Log "Monitoring: $($services.Keys -join ', ')"

$restartCount = 0

do {
    Start-Sleep -Seconds $CheckInterval
    $tracked = Get-TrackedPIDs
    
    if ($tracked.Count -eq 0) {
        Write-Log "No tracked PIDs found. Is the server running?"
        if ($Once) { break }
        continue
    }
    
    foreach ($name in $services.Keys) {
        $pid = $tracked[$name]
        if (-not $pid) { continue }
        
        if (-not (Test-ProcessAlive $pid)) {
            Write-Log "CRASH DETECTED: $name (PID $pid) is dead"
            $newPid = Restart-Service $name $services[$name]
            $restartCount++
            
            if ($newPid -eq 0) {
                Write-Log "WARNING: Could not restart $name after crash"
            }
        }
    }
    
    if ($Once) { break }
    
} while ($true)

Write-Log "Watchdog stopped (total restarts: $restartCount)"
