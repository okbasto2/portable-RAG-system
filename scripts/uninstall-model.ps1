<#
  uninstall-model.ps1 - Remove an installed GGUF model.

  Usage:
    powershell -ExecutionPolicy Bypass -File scripts\uninstall-model.ps1 [-File <model-filename>] [-Force]
  Or simply run uninstall-model.bat (interactive numbered menu).

  Deletes the .gguf from data\llama_models\. If the removed model was the
  active chat or embedding model, start-server.ps1 is reset to the shipped
  defaults (Qwen3.5-4B / embeddinggemma) and the semantic cache is cleared
  when the chat model changes.
#>
param(
    [string]$File,
    [string]$Python = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT      = Split-Path -Parent $SCRIPT_DIR
$MODELS    = Join-Path $ROOT "data\llama_models"
$SERVER    = Join-Path $SCRIPT_DIR "start-server.ps1"
$PYTHON    = if ($Python) { $Python } else { Join-Path $ROOT "apps\python_env\python.exe" }

$DEFAULT_CHAT_FILE  = "Qwen3.5-4B-Q4_K_M.gguf"
$DEFAULT_CHAT_ALIAS = "qwen3.5:4b"
$DEFAULT_EMBED_FILE  = "embeddinggemma-300M-Q8_0.gguf"
$DEFAULT_EMBED_ALIAS = "embeddinggemma"

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

function Get-ConfigValue {
    param([string]$VarName)
    $pat = '\$' + $VarName + ' = "([^"\r\n]*)"'
    $m = [regex]::Match([System.IO.File]::ReadAllText($SERVER), $pat)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-ModelLeaf {
    param([string]$VarName)
    $v = Get-ConfigValue -VarName $VarName
    if ($v) { return Split-Path $v -Leaf }
    return ""
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

# ── list / pick ────────────────────────────────────────
$models = @(Get-ChildItem (Join-Path $MODELS "*.gguf") -File -ErrorAction SilentlyContinue | Sort-Object Name)
if ($models.Count -eq 0) { Write-Host "No GGUF models found in data\llama_models."; exit 1 }

$chatName  = Get-ModelLeaf -VarName "MODEL_CHAT"
$embedName = Get-ModelLeaf -VarName "MODEL_EMBED"

if ([string]::IsNullOrWhiteSpace($File)) {
    Write-Host "Installed models:"
    for ($i = 0; $i -lt $models.Count; $i++) {
        $mark = ""
        if ($models[$i].Name -eq $chatName)      { $mark = "   <- active chat model" }
        elseif ($models[$i].Name -eq $embedName) { $mark = "   <- active embedding model" }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $models[$i].Name, $mark)
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

if ($target.Name -eq $DEFAULT_CHAT_FILE -or $target.Name -eq $DEFAULT_EMBED_FILE) {
    Write-Host "[warn] '$($target.Name)' is a shipped default model. Restore it with setup-portable.ps1 or install-model.bat."
}

# ── reset config if it was the active model ────────────
if ($target.Name -eq $chatName) {
    Write-Host "[i] Was the active chat model - restoring default ($DEFAULT_CHAT_FILE)..."
    $null = Set-ModelConfig -VarName "MODEL_CHAT" -FileName $DEFAULT_CHAT_FILE -ModelAlias $DEFAULT_CHAT_ALIAS -AliasNth 0
    Clear-Cache
    Write-Host "[i] Semantic cache cleared (answers from the removed model must not be replayed)."
} elseif ($target.Name -eq $embedName) {
    Write-Host "[i] Was the active embedding model - restoring default ($DEFAULT_EMBED_FILE)..."
    $null = Set-ModelConfig -VarName "MODEL_EMBED" -FileName $DEFAULT_EMBED_FILE -ModelAlias $DEFAULT_EMBED_ALIAS -AliasNth 1
    Write-Host "[warn] Knowledge-base vectors were indexed with the removed embedding model."
    Write-Host "       Re-index documents before relying on RAG answers."
} else {
    Write-Host "[i] start-server.ps1 unchanged (was not the active model)."
}

Write-Host ""
$c = Get-ModelLeaf -VarName "MODEL_CHAT";  if (-not $c) { $c = "<unknown>" }
$e = Get-ModelLeaf -VarName "MODEL_EMBED"; if (-not $e) { $e = "<unknown>" }
Write-Host ("Active chat model      : {0}" -f $c)
Write-Host ("Active embedding model : {0}" -f $e)
