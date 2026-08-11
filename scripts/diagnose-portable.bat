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

:: ── 4. Semantic Cache ────────────────────────────────
echo ===================================================
echo   [4/5] Semantic Cache
echo ===================================================

if exist "%SCRIPT_DIR%semantic-cache-server.py" (
    echo   [OK] scripts\semantic-cache-server.py
) else (
    echo   [MISS] scripts\semantic-cache-server.py
)

if exist "%ROOT_DIR%data\semantic_cache\cache.db" (
    echo   [OK] data\semantic_cache\cache.db ^(cached responses^)
) else (
    echo   [INFO] data\semantic_cache\cache.db not created yet ^(auto-created on first start^)
)

if exist "%ROOT_DIR%data\semantic_cache\config.json" (
    echo   [OK] data\semantic_cache\config.json
) else (
    echo   [INFO] data\semantic_cache\config.json missing ^(server writes defaults on first start^)
)

netstat -ano 2>nul | findstr /C:":11436" >nul
if %errorlevel%==0 (
    echo   [OK] Cache proxy RUNNING on port 11436
) else (
    echo   [INFO] Port 11436 not listening ^(semantic cache proxy stopped^)
)
echo.

:: ── 5. CUDA Runtime DLLs ─────────────────────────────
echo ===================================================
echo   [5/5] CUDA Runtime DLLs ^(needed for GPU inference^)
echo ===================================================

if exist "%ROOT_DIR%apps\llamacpp\cuda\llama-server.exe" (
    for %%D in (cudart64_12.dll cublas64_12.dll cublasLt64_12.dll) do (
        if exist "%ROOT_DIR%apps\llamacpp\cuda\%%D" (
            echo   [OK] apps\llamacpp\cuda\%%D
        ) else (
            echo   [MISS] apps\llamacpp\cuda\%%D
        )
    )
    echo.
    echo   NOTE: if any DLL above is MISSING, llama-server silently falls
    echo         back to CPU ^(~8 tok/s instead of 25+^). Re-run
    echo         scripts\setup-portable.ps1 to fetch the CUDA 12.4 runtime.
) else (
    echo   [INFO] CUDA build not installed ^(CPU-only mode^) - no runtime needed
)
echo.

pause
