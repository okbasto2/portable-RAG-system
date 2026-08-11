@echo off
SETLOCAL ENABLEEXTENSIONS
:: ===================================================
::   Enterprise AI Stack - Install Model (.bat wrapper)
::   Usage: install-model.bat [huggingface-gguf-url] [alias]
:: ===================================================

SET "SCRIPT_DIR=%~dp0scripts\"
SET "INSTALL_SCRIPT=%SCRIPT_DIR%install-model.ps1"

echo ===================================================
echo   Enterprise AI Stack - Install Chat Model
echo ===================================================
echo.

if "%~1"=="" (
    powershell -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%"
) else (
    powershell -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" -Url "%~1" -Alias "%~2"
)

echo.
pause
