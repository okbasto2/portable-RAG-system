@echo off
SETLOCAL
:: ===================================================
::   Enterprise AI Stack - Stopper (.bat wrapper)
:: --------------------------------------------------
::   Calls stop-server.ps1 which reads the PID file and
::   stops ONLY the processes that start-server.ps1 launched.
::   Graceful shutdown first, force-kill as fallback.
::
::   To run: double-click this file, or:
::     powershell -ExecutionPolicy Bypass -File stop-server.ps1
:: ===================================================

SET "ROOT_DIR=%~dp0"

echo ===================================================
echo   Enterprise AI Stack - Stopping...
echo ===================================================
echo.

powershell -ExecutionPolicy Bypass -File "%ROOT_DIR%stop-server.ps1"

echo.
echo Done.
pause
