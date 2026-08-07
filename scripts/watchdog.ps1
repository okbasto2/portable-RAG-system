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
        Env       = @{ DOCLING_SERVE_ENABLE_UI = "true" }
    }
    "OpenWebUI" = @{
        Exe       = "$APPS\python_env\Scripts\open-webui.exe"
        Args      = @('serve', '--port', '8080')
        Port      = 8080
        WorkDir   = "$ROOT"
        Env       = @{
            DATA_DIR         = "$DATA\openwebui_data"
            OLLAMA_BASE_URL  = "http://127.0.0.1:11434"
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

Write-Log "Watchdog started (Check interval: ${CheckInterval}s)"

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
