@echo off
SETLOCAL ENABLEEXTENSIONS
SET "SCRIPT_DIR=%~dp0"
SET "ROOT_DIR=%~dp0..\"

echo ===================================================
echo   Enterprise AI Stack - Diagnostic Report
echo ===================================================
echo.
echo   Running from: %ROOT_DIR%
echo   Computer: %COMPUTERNAME%
echo   Windows: 
ver
echo.

:: ── 1. VC++ Runtime ──────────────────────────────────
echo ===================================================
echo   [1/5] Visual C++ Redistributable
echo ===================================================
set HAS_VC=0
if exist "%SystemRoot%\System32\vcruntime140.dll" set HAS_VC=1
if exist "%ROOT_DIR%apps\python_env\vcruntime140.dll" (
    echo   [OK] vcruntime140.dll found in portable Python env
) else (
    echo   [ERROR] vcruntime140.dll NOT found in portable package
)
if %HAS_VC%==1 (
    echo   [OK] System has vcruntime140.dll installed globally
) else (
    echo   [INFO] System does NOT have vcruntime140.dll (fresh Windows)
)
echo.

:: ── 2. Portable Python ───────────────────────────────
echo ===================================================
echo   [2/5] Portable Python
echo ===================================================
SET "PYTHON_EXE=%ROOT_DIR%apps\python_env\python.exe"
if exist "%PYTHON_EXE%" (
    echo   [OK] python.exe found
    "%PYTHON_EXE%" --version 2>nul
) else (
    echo   [ERROR] python.exe not found at: %PYTHON_EXE%
)
echo.

:: ── 3. Service Executables ───────────────────────────
echo ===================================================
echo   [3/5] Service Executables
echo ===================================================

if exist "%ROOT_DIR%apps\qdrant\qdrant.exe" (
    echo   [OK] apps\qdrant\qdrant.exe
) else (
    echo   [MISS] apps\qdrant\qdrant.exe
)

if exist "%ROOT_DIR%apps\llamacpp\cpu\llama-server.exe" (
    echo   [OK] apps\llamacpp\cpu\llama-server.exe
) else (
    echo   [MISS] apps\llamacpp\cpu\llama-server.exe
)

if exist "%ROOT_DIR%apps\llamacpp\cuda\llama-server.exe" (
    echo   [OK] apps\llamacpp\cuda\llama-server.exe ^(CUDA build^)
) else (
    echo   [INFO] apps\llamacpp\cuda\llama-server.exe not present ^(CPU-only mode^)
)

if exist "%ROOT_DIR%data\llama_models\Qwen3.5-4B-Q4_K_M.gguf" (
    echo   [OK] data\llama_models\Qwen3.5-4B-Q4_K_M.gguf
) else (
    echo   [MISS] data\llama_models\Qwen3.5-4B-Q4_K_M.gguf ^(chat model^)
)

if exist "%ROOT_DIR%data\llama_models\embeddinggemma-300M-Q8_0.gguf" (
    echo   [OK] data\llama_models\embeddinggemma-300M-Q8_0.gguf
) else (
    echo   [MISS] data\llama_models\embeddinggemma-300M-Q8_0.gguf ^(embedding model^)
)
echo.

pause
