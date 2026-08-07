<# 
  stop-server.ps1
  Enterprise AI Stack -- Graceful Shutdown
  
  Reads PIDs from .server-pids.txt and stops each process.
  Tries graceful shutdown first (CloseMainWindow), then force-kills.
  Only targets the exact processes that were started by start-server.ps1.
#>

$ErrorActionPreference = "Continue"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$PID_FILE = "$ROOT\.server-pids.txt"

Write-Output "===================================================="
Write-Output "  Stopping Enterprise AI Stack"
Write-Output "===================================================="

if (-not (Test-Path $PID_FILE)) {
    Write-Output "WARNING: No PID file found at $PID_FILE"
    Write-Output "Services may have been started manually or already stopped."
    Write-Output "Falling back to image-name matching..."
    Write-Output ""
    
    $fallbackTitles = @("Qdrant", "Ollama", "Docling", "OpenWebUI", "Open WebUI")
    foreach ($title in $fallbackTitles) {
        $procs = Get-Process | Where-Object { $_.MainWindowTitle -like "*$title*" }
        foreach ($p in $procs) {
            Write-Output "  Stopping $($p.ProcessName) (PID $($p.Id))..."
            try { $p.CloseMainWindow(); Start-Sleep -Seconds 2 } catch { }
            if (-not $p.HasExited) { $p.Kill() }
            Write-Output "    done"
        }
    }
    Write-Output ""
    Write-Output "===================================================="
    Write-Output "  Shutdown complete (fallback mode)"
    Write-Output "===================================================="
    exit 0
}

$entries = Get-Content $PID_FILE | Where-Object { $_ -match '^(.+)=(\d+)$' } | ForEach-Object {
    [PSCustomObject]@{ Name = $matches[1]; PID = [int]$matches[2] }
}

if ($entries.Count -eq 0) {
    Write-Output "PID file was empty -- nothing to stop."
    Remove-Item $PID_FILE -Force
    exit 0
}

$stopOrder = @("OpenWebUI", "Docling", "Ollama", "Qdrant")
$errors = 0

foreach ($name in $stopOrder) {
    $entry = $entries | Where-Object { $_.Name -eq $name }
    if (-not $entry) { continue }
    
    Write-Output "  [$name] PID=$($entry.PID)"
    $proc = Get-Process -Id $entry.PID -ErrorAction SilentlyContinue
    
    if (-not $proc) {
        Write-Output "    already stopped"
        continue
    }
    
    $graceful = $false
    try {
        $proc.CloseMainWindow()
        $proc.WaitForExit(5000)
        if ($proc.HasExited) { $graceful = $true }
    } catch { }
    
    if ($graceful) {
        Write-Output "    stopped gracefully"
    } else {
        Write-Output "    force-stopping..."
        try {
            Stop-Process -Id $entry.PID -Force -ErrorAction Stop
            Write-Output "    done"
        } catch {
            Write-Output "    FAILED: $_"
            $errors++
        }
    }
}

Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "===================================================="
Write-Output "  Shutdown complete"
if ($errors -gt 0) { Write-Output "  $errors error(s) during shutdown" }
Write-Output "===================================================="
