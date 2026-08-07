@echo off
SETLOCAL
:: ===================================================
::   Enterprise AI Stack - Stopper (.bat wrapper)
:: ===================================================

SET "ROOT_DIR=%~dp0"
SET "STOP_SCRIPT=%ROOT_DIR%scripts\stop-server.ps1"

echo ===================================================
echo   Enterprise AI Stack - Stopping...
echo ===================================================
echo.

powershell -ExecutionPolicy Bypass -File "%STOP_SCRIPT%"

echo.
echo Done.
pause
