@echo off
SETLOCAL
SET "SCRIPT_DIR=%~dp0"
SET "ROOT_DIR=%~dp0..\"
SET "PYTHON=%ROOT_DIR%apps\python_env\python.exe"
SET "FIXER=%SCRIPT_DIR%fix-portable.py"

echo ===================================================
echo   Enterprise AI Stack - Portable Path Fixer
echo ===================================================
echo Root : %ROOT_DIR%
echo Python: %PYTHON%
echo.

if not exist "%PYTHON%" (
    echo [ERROR] Portable python not found at: %PYTHON%
    pause
    exit /b 1
)
if not exist "%FIXER%" (
    echo [ERROR] fix-portable.py not found at: %FIXER%
    pause
    exit /b 1
)

"%PYTHON%" "%FIXER%"
set RC=%ERRORLEVEL%

if "%RC%"=="0" (
    echo.
    echo [OK] Portable paths fixed.
) else (
    echo.
    echo [ERROR] fix-portable.py exited with code %RC%.
)
ENDLOCAL
