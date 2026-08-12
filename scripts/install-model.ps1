<#
  install-model.ps1 - Install a new chat model for llama.cpp (router mode).

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts\install-model.ps1 [-Url <gguf-url>] [-Alias <alias>] [-Force]
  Or simply run install-model.bat (prompts for anything missing).

  What it does:
    1. Validates the URL (must point to a .gguf file)
    2. Downloads it into data\llama_models\ (or reuses an existing valid file)
    3. Registers it in data\llama_models\models.ini under <alias> - it becomes
       selectable in Open WebUI immediately after a restart (router mode,
       no start-server.ps1 edits needed; other installed models stay selectable)
    4. Offers to restart the stack if the chat server is running

  Notes:
    - The model must be GGUF (llama.cpp format). Use a HuggingFace
      /resolve/main/ link to the exact file.
    - The 6 GB GPU holds one model at a time (--models-max 1); llama-server
      swaps them on demand. First use of a model takes a few seconds to load.
    - The semantic cache is per-model, so answers never cross models.
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
$MODELS_INI = Join-Path $MODELS "models.ini"
$SERVER    = Join-Path $SCRIPT_DIR "start-server.ps1"
$PYTHON    = if ($Python) { $Python } else { Join-Path $ROOT "apps\python_env\python.exe" }

# ── helpers ────────────────────────────────────────────
function Test-GgufMagic {
    param([string]$Path)
    # Read only the first 4 bytes via a stream. ReadAllBytes throws on files >= 2 GB.
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $buf = New-Object byte[] 4
            $read = $fs.Read($buf, 0, 4)
            return ($read -eq 4 -and $buf[0] -eq 0x47 -and $buf[1] -eq 0x47 -and $buf[2] -eq 0x55 -and $buf[3] -eq 0x46)
        } finally {
            $fs.Dispose()
        }
    } catch {
        return $false
    }
}

function Set-IniModel {
    param([string]$IniPath, [string]$ModelAlias, [string]$ModelPath)
    # sanitize the alias so it can't break INI syntax (section names / values)
    $ModelAlias = $ModelAlias -replace '[\[\]=;$]', '-'
    $section = "[$ModelAlias]`r`nmodel = $ModelPath`r`n"
    if (-not (Test-Path $IniPath)) {
        $content = "version = 1`r`n`r`n" + $section
    } else {
        $content = [System.IO.File]::ReadAllText($IniPath)
        $pattern = '(?m)^\[' + [regex]::Escape($ModelAlias) + '\]\s*$[\s\S]*?(?=^\[|\z)'
        if ([regex]::IsMatch($content, $pattern)) {
            $content = [regex]::Replace($content, $pattern, $section)
        } else {
            if (-not $content.EndsWith("`n")) { $content += "`r`n" }
            $content += "`r`n" + $section
        }
    }
    [System.IO.File]::WriteAllText($IniPath, $content, (New-Object System.Text.UTF8Encoding($false)))
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

# ── 3. download (or reuse an existing valid file) ──────
$dest = Join-Path $MODELS $fileName
New-Item -ItemType Directory -Force -Path $MODELS | Out-Null

$needDownload = $true
if (Test-Path $dest) {
    if (Test-GgufMagic $dest) {
        # Valid GGUF already on disk - reuse it (no multi-GB re-download)
        if (-not $Force) {
            $ans = Read-Host "$fileName already installed - use it as-is? [y/N]"
            if ($ans -notmatch '^[yY]') { Write-Host "Aborted."; exit 1 }
        }
        Write-Host "[i] Using existing file: $fileName"
        $needDownload = $false
    } else {
        if (-not $Force) {
            $ans = Read-Host "$fileName exists but is not a valid GGUF - re-download? [y/N]"
            if ($ans -notmatch '^[yY]') { Write-Host "Aborted."; exit 1 }
        }
        Write-Host "[i] Re-downloading $fileName ..."
    }
} else {
    Write-Host "[i] Downloading $fileName ..."
}

if ($needDownload) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
    } catch {
        if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
        throw "Download failed: $($_.Exception.Message)"
    }
    # GGUF magic check - a 404/HTML error page would otherwise be saved as .gguf
    if (-not (Test-GgufMagic $dest)) {
        Remove-Item $dest -Force
        throw "Downloaded file is not a valid GGUF (magic bytes are not 'GGUF'). Check the URL."
    }
}

$sizeGB = [math]::Round((Get-Item $dest).Length / 1GB, 2)
Write-Host "[OK] $fileName ($sizeGB GB)"
if ($sizeGB -gt 6) {
    Write-Host "[warn] Larger than this host's 6 GB GPU VRAM - expect partial offload or CPU-only fallback."
}

# ── 4. register in models.ini ──────────────────────────
$relPath = "data\llama_models\" + $fileName
Set-IniModel -IniPath $MODELS_INI -ModelAlias $Alias -ModelPath $relPath
Write-Host "[OK] Registered '$Alias' in models.ini -> $relPath"
Write-Host "[i] All installed models stay selectable in Open WebUI (router mode)."

# ── 5. restart hint ────────────────────────────────────
$tcp = $false
try { $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port 11434 -WarningAction SilentlyContinue -InformationLevel Quiet } catch { }
Write-Host ""
if ($tcp) {
    $ans = Read-Host "Chat server (:11434) is running without the new model. Restart the stack now? [y/N]"
    if ($ans -match '^[yY]') {
        & "$SCRIPT_DIR\stop-server.ps1"
        Write-Host "Stack stopped. Start it again with start-project.bat - '$Alias' will appear in Open WebUI."
    } else {
        Write-Host "Restart the stack later (stop-project.bat then start-project.bat) to see '$Alias'."
    }
} else {
    Write-Host "Done. Start the stack (start-project.bat) - '$Alias' will appear in Open WebUI."
}
