@echo off
SETLOCAL
:: fix-portable.bat
:: Re-points every pip launcher in apps\python_env\Scripts to the current
:: location of this folder, AND copies VC++ runtime DLLs alongside qdrant.
:: Run this ONCE after copying the folder to a new PC, a new drive letter,
:: or a new user. Also safe to run after a future `pip install <pkg>` that
:: drops new *.exe launchers into Scripts\.
::
:: It is idempotent: running it twice does nothing the second time.

SET "ROOT_DIR=%~dp0"
SET "PYTHON=%ROOT_DIR%apps\python_env\python.exe"
SET "FIXER=%ROOT_DIR%fix-portable.py"

echo ===================================================
echo   Enterprise AI Stack - Portable Path Fixer
echo ===================================================
echo Root : %ROOT_DIR%
echo Python: %PYTHON%
echo.

if not exist "%PYTHON%" (
    echo [ERROR] Portable python not found at:
    echo   %PYTHON%
    echo Expected layout: apps\python_env\python.exe
    pause
    exit /b 1
)
if not exist "%FIXER%" (
    echo [ERROR] fix-portable.py not found at:
    echo   %FIXER%
    pause
    exit /b 1
)

"%PYTHON%" "%FIXER%"
set RC=%ERRORLEVEL%

if "%RC%"=="0" (
    echo.
    echo [OK] Portable paths fixed. You can now run start-project.bat.
) else (
    echo.
    echo [ERROR] fix-portable.py exited with code %RC%. Open the logs above.
)
ENDLOCAL
