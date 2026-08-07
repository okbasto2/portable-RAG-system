@echo off
SETLOCAL ENABLEEXTENSIONS
:: ===================================================
::   diagnose-portable.bat
::   Enterprise AI Stack - Diagnostic Tool
::
::   Checks for common issues that prevent startup
::   on fresh Windows 11 machines.
::
::   Double-click to run, or:
::     diagnose-portable.bat
:: ===================================================

SET "ROOT_DIR=%~dp0"

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
    if not exist "%ROOT_DIR%apps\qdrant\vcruntime140.dll" (
        echo   [WARN] DLL not in qdrant folder - qdrant.exe may fail to start!
        echo   Fix: copy apps\python_env\vcruntime140.dll to apps\qdrant\
    ) else (
        echo   [OK] DLL also present in apps\qdrant\ (where qdrant.exe looks)
    )
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
    if errorlevel 1 (
        echo   [FAIL] python.exe failed to launch! Possible DLL issue.
    ) else (
        echo   [OK] python.exe works
    )
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

if exist "%ROOT_DIR%apps\ollama\ollama.exe" (
    echo   [OK] apps\ollama\ollama.exe
) else (
    echo   [MISS] apps\ollama\ollama.exe
)

if exist "%ROOT_DIR%apps\python_env\Scripts\docling-serve.exe" (
    echo   [OK] apps\python_env\Scripts\docling-serve.exe
) else (
    echo   [MISS] apps\python_env\Scripts\docling-serve.exe
)

if exist "%ROOT_DIR%apps\python_env\Scripts\open-webui.exe" (
    echo   [OK] apps\python_env\Scripts\open-webui.exe
) else (
    echo   [MISS] apps\python_env\Scripts\open-webui.exe
)
echo.

:: ── 4. Port Availability ─────────────────────────────
echo ===================================================
echo   [4/5] Port Availability
echo ===================================================
set PORTS_FREE=1
for %%p in (6333 6334 11434 5001 8080) do (
    netstat -an | findstr ":%%p " | findstr "LISTENING" >nul 2>&1
    if errorlevel 1 (
        echo   [OK] Port %%p is free
    ) else (
        echo   [WARN] Port %%p is IN USE - service will fail to bind!
        set PORTS_FREE=0
    )
)
echo.

:: ── 5. Quick Service Smoke Test ───────────────────────
echo ===================================================
echo   [5/5] Quick Service Tests
echo ===================================================
echo   Testing qdrant.exe (will run for 3 secs then stop)...
start "" /B "%ROOT_DIR%apps\qdrant\qdrant.exe" --uri http://127.0.0.1:6333 >nul 2>&1
ping -n 4 127.0.0.1 >nul 2>&1
tasklist /FI "IMAGENAME eq qdrant.exe" 2>nul | findstr "qdrant.exe" >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] qdrant.exe could not start (most likely missing VC++ runtime)
    echo   HINT: Install Visual C++ Redistributable from:
    echo         https://aka.ms/vs/17/release/vc_redist.x64.exe
) else (
    echo   [OK] qdrant.exe started successfully
    taskkill /F /IM qdrant.exe >nul 2>&1
)
echo.

echo   Testing ollama.exe...
start "" /B "%ROOT_DIR%apps\ollama\ollama.exe" serve >nul 2>&1
ping -n 4 127.0.0.1 >nul 2>&1
tasklist /FI "IMAGENAME eq ollama.exe" 2>nul | findstr "ollama.exe" >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] ollama.exe could not start
) else (
    echo   [OK] ollama.exe started successfully
    taskkill /F /IM ollama.exe >nul 2>&1
)
echo.

:: ── Summary ────────────────────────────────────────────
echo ===================================================
echo   SUMMARY
echo ===================================================
echo.
echo   If you see any [FAIL] or [ERROR] above, those are
echo   the issues preventing startup from working.
echo.
echo   Most common fix: Install Visual C++ Redistributable
echo     Download: https://aka.ms/vs/17/release/vc_redist.x64.exe
echo.
echo   If the diagnostic passes but start-project.bat still
echo   hangs, try running it from a command prompt:
echo     cd /d "%ROOT_DIR%"
echo     start-project.bat
echo   This lets you see console output that might otherwise
echo   flash by.
echo.
echo ===================================================
echo   Diagnostic complete.
echo ===================================================
pause
