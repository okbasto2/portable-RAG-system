<#
  uninstall-model.ps1 - Remove an installed GGUF model (router mode).

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts\uninstall-model.ps1 [-File <model-filename>] [-Force]
  Or simply run uninstall-model.bat (interactive numbered menu).

  Deletes the .gguf from data\llama_models\ and removes its section from
  models.ini, so the model disappears from Open WebUI's picker. Other
  installed models are unaffected. The semantic cache is per-model, so no
  cache clearing is needed.
#>
param(
    [string]$File,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT      = Split-Path -Parent $SCRIPT_DIR
$MODELS    = Join-Path $ROOT "data\llama_models"
$MODELS_INI = Join-Path $MODELS "models.ini"

# ── helpers ────────────────────────────────────────────
function Get-IniAlias {
    param([string]$IniPath, [string]$FileName)
    if (-not (Test-Path $IniPath)) { return "" }
    $content = [System.IO.File]::ReadAllText($IniPath)
    $pattern = '(?m)^\[([^\]]*)\][^\S\r\n]*\r?\nmodel = [^\r\n]*' + [regex]::Escape($FileName) + '[^\r\n]*$'
    $m = [regex]::Match($content, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Remove-IniModel {
    param([string]$IniPath, [string]$FileName)
    if (-not (Test-Path $IniPath)) { return $false }
    $content = [System.IO.File]::ReadAllText($IniPath)
    # remove the whole section (header + model line) plus its trailing blank line(s)
    $pattern = '(?m)^\[[^\]]*\]\s*$[^\S\r\n]*\r?\nmodel = [^\r\n]*' + [regex]::Escape($FileName) + '[^\r\n]*(?:\r?\n){0,2}'
    $new = [regex]::Replace($content, $pattern, '')
    # collapse any resulting runs of blank lines
    $new = $new -replace "(\r?\n){3,}", "`r`n`r`n"
    if ($new -ne $content) {
        [System.IO.File]::WriteAllText($IniPath, $new, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    }
    return $false
}

# ── list / pick ────────────────────────────────────────
$models = @(Get-ChildItem (Join-Path $MODELS "*.gguf") -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($models.Count -eq 0) { Write-Host "No GGUF models found in data\llama_models."; exit 1 }

if ([string]::IsNullOrWhiteSpace($File)) {
    Write-Host "Installed models:"
    for ($i = 0; $i -lt $models.Count; $i++) {
        $a = Get-IniAlias -IniPath $MODELS_INI -FileName $models[$i].Name
        $aliasTxt = if ($a) { "   (alias: $a)" } else { "   (not registered in models.ini)" }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $models[$i].Name, $aliasTxt)
    }
    $choice = Read-Host "Number to uninstall"
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $models.Count) {
        Write-Host "Invalid choice."
        exit 1
    }
    $target = $models[$idx - 1]
} else {
    $target = $models | Where-Object { $_.Name -eq $File }
    if (-not $target) { Write-Host "No model named '$File' in data\llama_models."; exit 1 }
}

# ── confirm + delete ───────────────────────────────────
if (-not $Force) {
    $ans = Read-Host "Delete $($target.Name) permanently? [y/N]"
    if ($ans -notmatch '^[yY]') { Write-Host "Aborted."; exit 1 }
}

try {
    Remove-Item $target.FullName -Force
    Write-Host "[OK] Deleted $($target.Name)"
} catch {
    Write-Host "[error] Could not delete $($target.Name) - is the stack running with this model loaded?"
    Write-Host "        Stop the stack first (stop-project.bat) and try again."
    exit 1
}

# ── unregister from models.ini ─────────────────────────
$removed = Remove-IniModel -IniPath $MODELS_INI -FileName $target.Name
if ($removed) {
    Write-Host "[OK] Removed from models.ini - '$($target.Name)' will disappear from Open WebUI after restart."
} else {
    Write-Host "[i] Was not registered in models.ini (file removed anyway)."
}

$ini = if (Test-Path $MODELS_INI) { [System.IO.File]::ReadAllText($MODELS_INI) } else { "" }
if ($ini -notmatch '(?m)^\[[^\]]*\]\s*$[^\S\r\n]*\r?\nmodel = ') {
    Write-Host ""
    Write-Host "[warn] No chat models left registered. Install one with install-model.bat before restarting the stack."
}
