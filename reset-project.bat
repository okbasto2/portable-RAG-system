@echo off
:: reset-project.bat
:: Wipes all user data (users, chats, documents) but keeps config and models.
:: Run this before copying the project to a new machine.

SET "ROOT=%~dp0"
SET "PYTHON=%ROOT%apps\python_env\python.exe"
SET "SCRIPT=%ROOT%reset-data.py"

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
echo.
echo The following will be KEPT:
echo   - Config settings (RAG, model endpoints, etc.)
echo   - Ollama model weights
echo   - Application code
echo.
choice /C YN /M "Are you sure you want to proceed"
if errorlevel 2 exit /b 0

"%PYTHON%" "%SCRIPT%"
pause
