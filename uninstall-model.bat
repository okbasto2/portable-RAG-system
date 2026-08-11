@echo off
SETLOCAL ENABLEEXTENSIONS
:: ===================================================
::   Enterprise AI Stack - Uninstall Model (.bat wrapper)
::   Usage: uninstall-model.bat [model-filename]
:: ===================================================

SET "SCRIPT_DIR=%~dp0scripts\"
SET "UNINSTALL_SCRIPT=%SCRIPT_DIR%uninstall-model.ps1"

echo ===================================================
echo   Enterprise AI Stack - Uninstall Model
echo ===================================================
echo.

if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%UNINSTALL_SCRIPT%"
) else (
    powershell -ExecutionPolicy Bypass -File "%UNINSTALL_SCRIPT%" -File "%~1"
)

echo.
pause
