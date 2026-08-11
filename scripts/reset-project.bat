@echo off
SETLOCAL
SET "SCRIPT_DIR=%~dp0"
SET "ROOT_DIR=%~dp0..\"
SET "PYTHON=%ROOT_DIR%apps\python_env\python.exe"
SET "SCRIPT=%SCRIPT_DIR%reset-data.py"

echo ===================================================
echo   Enterprise AI Stack — Data Reset
echo ===================================================
echo.
echo This will delete ALL user data:
echo   - User accounts and passwords
echo   - Chat conversations
echo   - Uploaded documents
echo   - Knowledge base entries
echo   - Logs and caches
echo   - Cached AI responses (semantic cache)
echo.
echo The following will be KEPT:
echo   - Config settings (RAG, model endpoints, semantic cache threshold, etc.)
echo   - llama.cpp model weights
echo   - Application code
echo.
choice /C YN /M "Are you sure you want to proceed"
if errorlevel 2 exit /b 0

if exist "%PYTHON%" (
    "%PYTHON%" "%SCRIPT%"
) else (
    echo [ERROR] Portable python not found at %PYTHON%
)
pause
