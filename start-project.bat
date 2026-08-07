@echo off
SETLOCAL ENABLEEXTENSIONS
:: ===================================================
::   Enterprise AI Stack - Server Launcher (.bat wrapper)
:: --------------------------------------------------
::   This is a thin wrapper that calls start-server.ps1.
::   The PowerShell script handles: GPU detection, PID
::   tracking, log redirection, and health checks.
::
::   To run: double-click this file, or:
::     powershell -ExecutionPolicy Bypass -File start-server.ps1
::
::   NEW PC? Run diagnose-portable.bat first to check
::   for common issues (missing DLLs, port conflicts, etc.)
::
::   WHAT TO EXPECT: Each service starts and is health-checked.
::   You'll see dots (...) while each service warms up.
::   If a service fails, the error is shown immediately.
::   After all services pass, a summary is shown.
:: ===================================================

SET "ROOT_DIR=%~dp0"
SET "PYTHON_EXE=%ROOT_DIR%apps\python_env\python.exe"
SET "FIX_FLAG=%ROOT_DIR%.portable-fixed"

echo ===================================================
echo   Enterprise AI Stack - Starting...
echo   Location: %ROOT_DIR%
echo ===================================================
echo.
echo TIP: If this hangs, run diagnose-portable.bat first
echo      to check for common issues.
echo.

:: ----------------------------------------------------------------
:: 0. First-run fixer (portable path repair + VC runtime setup)
::    Runs once per location. Delete .portable-fixed to re-run.
:: ----------------------------------------------------------------
if not exist "%FIX_FLAG%" (
    echo [First run] Running portable fixes...
    echo   - Making Python launchers relocatable
    echo   - Copying VC++ runtime DLLs alongside qdrant
    if exist "%PYTHON_EXE%" (
        "%PYTHON_EXE%" "%ROOT_DIR%fix-portable.py"
        if errorlevel 1 (
            echo   WARNING: fix-portable.py reported errors.
        )
    ) else (
        echo   WARNING: python.exe not found, skipping fixes
    )
    type nul > "%FIX_FLAG%"
    echo   Done.
    echo.
)

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Portable python not found at: %PYTHON_EXE%
    echo Expected layout: apps\python_env\python.exe
    pause
    exit /b 1
)

:: ----------------------------------------------------------------
:: Delegate to the PowerShell server launcher
:: ----------------------------------------------------------------
echo Launching services via PowerShell...
echo.

powershell -ExecutionPolicy Bypass -File "%ROOT_DIR%start-server.ps1"

echo.
echo Server process ended. Run stop-server.ps1 to ensure clean shutdown.
pause
