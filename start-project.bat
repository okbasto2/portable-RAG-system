@echo off
SETLOCAL ENABLEEXTENSIONS
:: ===================================================
::   Enterprise AI Stack - Server Launcher (.bat wrapper)
:: ===================================================

SET "ROOT_DIR=%~dp0"
SET "PYTHON_EXE=%ROOT_DIR%apps\python_env\python.exe"
SET "FIX_FLAG=%ROOT_DIR%.portable-fixed"
SET "FIXER_SCRIPT=%ROOT_DIR%scripts\fix-portable.py"
SET "START_SCRIPT=%ROOT_DIR%scripts\start-server.ps1"

echo ===================================================
echo   Enterprise AI Stack - Starting...
echo   Location: %ROOT_DIR%
echo ===================================================
echo.

if not exist "%FIX_FLAG%" (
    echo [First run] Running portable fixes...
    if exist "%PYTHON_EXE%" (
        if exist "%FIXER_SCRIPT%" (
            "%PYTHON_EXE%" "%FIXER_SCRIPT%"
        )
    )
    type nul > "%FIX_FLAG%"
    echo   Done.
    echo.
)

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Portable python not found at: %PYTHON_EXE%
    echo Run setup-portable.ps1 first: powershell -ExecutionPolicy Bypass -File scripts\setup-portable.ps1
    pause
    exit /b 1
)

echo Launching services via PowerShell...
echo.

powershell -ExecutionPolicy Bypass -File "%START_SCRIPT%"

echo.
echo Server process ended.
pause
