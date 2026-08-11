<#
  install-model.ps1 - Install a new chat model for llama.cpp.

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts\install-model.ps1 [-Url <gguf-url>] [-Alias <alias>] [-Force]
  Or simply run install-model.bat (prompts for anything missing).

  What it does:
    1. Validates the URL (must point to a .gguf file)
    2. Downloads it into data\llama_models\
    3. Points $MODEL_CHAT and the chat --alias in start-server.ps1 at the new model
    4. Clears the semantic cache (old-model answers must not be replayed)
    5. Offers to restart the stack if the chat server is running

  Notes:
    - The model must be GGUF (llama.cpp format). Use a HuggingFace
      /resolve/main/ link to the exact file, e.g.
      https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf
    - For this host's 6 GB GPU, stay around 4B @ Q4_K_M (fully offloaded)
      or up to ~8B @ Q4 (partial offload). Bigger models run on CPU.
#>
param(
    [string]$Url,
    [string]$Alias,
    [string]$Python = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT      = Split-Path -Parent $SCRIPT_DIR
$MODELS    = Join-Path $ROOT "data\llama_models"
$SERVER    = Join-Path $SCRIPT_DIR "start-server.ps1"
$PYTHON    = if ($Python) { $Python } else { Join-Path $ROOT "apps\python_env\python.exe" }

# ── helpers ────────────────────────────────────────────
function Replace-Nth {
    param([string]$Content, [string]$Pattern, [string]$Replacement, [int]$Nth = 0)
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern)
    $m = $regex.Match($Content)
    for ($i = 0; $i -lt $Nth -and $m.Success; $i++) { $m = $m.NextMatch() }
    if (-not $m.Success) { return $null }
    return $Content.Substring(0, $m.Index) + $Replacement + $Content.Substring($m.Index + $m.Length)
}

function Set-ModelConfig {
    param([string]$VarName, [string]$FileName, [string]$ModelAlias, [int]$AliasNth)
    $content = [System.IO.File]::ReadAllText($SERVER)
    $orig = $content
    $content = Replace-Nth -Content $content -Pattern ('\$' + $VarName + ' = "[^"\r\n]*"') `
        -Replacement ('$' + $VarName + ' = "$DATA\llama_models\' + $FileName + '"') -Nth 0
    if ($null -eq $content) { throw "Could not locate the `$$VarName line in start-server.ps1 (format changed?)" }
    $content = Replace-Nth -Content $content -Pattern "('--alias',[ \t]*)'[^']*'" `
        -Replacement ("'--alias', '" + $ModelAlias + "'") -Nth $AliasNth
    if ($null -eq $content) { throw "Could not locate the --alias line for $VarName (format changed?)" }
    if ($content -ne $orig) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($SERVER, $content, $utf8)
        return $true
    }
    return $false
}

function Clear-Cache {
    if (Test-Path $PYTHON) {
        Write-Host "[i] Clearing semantic cache..."
        & $PYTHON "$SCRIPT_DIR\clear-semantic-cache.py"
    } else {
        Write-Host "[warn] Portable python not found - skipping cache clear."
        Write-Host "       Run later: apps\python_env\python.exe scripts\clear-semantic-cache.py"
    }
}

# ── 1. URL ─────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Url)) {
    $Url = (Read-Host "HuggingFace GGUF download URL").Trim()
}
$Url = $Url.Trim()
if (-not $Url.StartsWith("http")) { throw "URL must start with http(s)://" }

$fileName = $Url -replace '\?.*$', ''
$fileName = $fileName.Substring($fileName.LastIndexOf('/') + 1)
if (-not $fileName.EndsWith('.gguf', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "URL must point to a .gguf file (got: '$fileName'). Use a HuggingFace /resolve/main/ link to the exact file."
}

# ── 2. alias ───────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($Alias)) {
    $Alias = (($fileName -replace '\.gguf$', '') -replace '\s+', '-').ToLower()
}

# ── 3. download ────────────────────────────────────────
$dest = Join-Path $MODELS $fileName
New-Item -ItemType Directory -Force -Path $MODELS | Out-Null

if (Test-Path $dest) {
    if (-not $Force) {
        $ans = Read-Host "$fileName already exists - overwrite? [y/N]"
        if ($ans -notmatch '^[yY]') { Write-Host "Aborted."; exit 1 }
    }
    Write-Host "[i] Re-downloading $fileName ..."
} else {
    Write-Host "[i] Downloading $fileName ..."
}

try {
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
} catch {
    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
    throw "Download failed: $($_.Exception.Message)"
}

# GGUF magic check - a 404/HTML error page would otherwise be saved as .gguf
$head = [System.IO.File]::ReadAllBytes($dest)
if (-not ($head.Length -ge 4 -and $head[0] -eq 0x47 -and $head[1] -eq 0x47 -and $head[2] -eq 0x55 -and $head[3] -eq 0x46)) {
    Remove-Item $dest -Force
    throw "Downloaded file is not a valid GGUF (magic bytes are not 'GGUF'). Check the URL."
}
$sizeGB = [math]::Round((Get-Item $dest).Length / 1GB, 2)
Write-Host "[OK] Downloaded $fileName ($sizeGB GB)"
if ($sizeGB -gt 6) {
    Write-Host "[warn] Larger than this host's 6 GB GPU VRAM - expect partial offload or CPU-only fallback."
}

# ── 4. patch start-server.ps1 ──────────────────────────
$changed = Set-ModelConfig -VarName "MODEL_CHAT" -FileName $fileName -ModelAlias $Alias -AliasNth 0
if ($changed) {
    Write-Host "[OK] start-server.ps1 -> chat model: $fileName (alias: $Alias)"
} else {
    Write-Host "[i] start-server.ps1 already configured for: $fileName"
}

# ── 5. semantic cache ──────────────────────────────────
Clear-Cache

# ── 6. restart hint ────────────────────────────────────
$tcp = $false
try { $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port 11434 -WarningAction SilentlyContinue -InformationLevel Quiet } catch { }
Write-Host ""
if ($tcp) {
    $ans = Read-Host "Chat server (:11434) is still running the old model. Stop the stack now? [y/N]"
    if ($ans -match '^[yY]') {
        & "$SCRIPT_DIR\stop-server.ps1"
        Write-Host "Stack stopped. Start it again with start-project.bat to load '$Alias'."
    } else {
        Write-Host "Restart the stack later (stop-project.bat then start-project.bat) to load '$Alias'."
    }
} else {
    Write-Host "Done. Start the stack (start-project.bat) to load the new model '$Alias'."
}
