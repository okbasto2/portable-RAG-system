<# 
  stop-server.ps1
  Enterprise AI Stack -- Graceful Shutdown
#>

$ErrorActionPreference = "Continue"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path -Parent $SCRIPT_DIR
$PID_FILE = "$ROOT\.server-pids.txt"

Write-Output "===================================================="
Write-Output "  Stopping Enterprise AI Stack"
Write-Output "===================================================="

if (-not (Test-Path $PID_FILE)) {
    Write-Output "WARNING: No PID file found at $PID_FILE"
    Write-Output "Falling back to image-name matching..."
    Write-Output ""
    
    $fallbackTitles = @("Qdrant", "llama-server", "semantic-cache-server", "Docling", "OpenWebUI", "Open WebUI")
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

$stopOrder = @("OpenWebUI", "Docling", "SemanticCache", "LlamaEmbed", "LlamaChat", "Qdrant")

foreach ($name in $stopOrder) {
    $entry = $entries | Where-Object { $_.Name -eq $name }
    if (-not $entry) { continue }
    
    Write-Output "  [$name] PID=$($entry.PID)"
    $proc = Get-Process -Id $entry.PID -ErrorAction SilentlyContinue
    if ($proc) {
        try {
            $proc.CloseMainWindow() | Out-Null
            Start-Sleep -Seconds 1
            if (-not $proc.HasExited) {
                $proc.Kill()
            }
            Write-Output "    [OK] Stopped"
        } catch {
            Write-Output "    [WARN] Force killing..."
            Stop-Process -Id $entry.PID -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Output "    Already stopped"
    }
}

Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue
Write-Output ""
Write-Output "===================================================="
Write-Output "  Shutdown complete"
Write-Output "===================================================="
