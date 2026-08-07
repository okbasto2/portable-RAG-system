@echo off
:: open-database.bat
:: Opens the Open WebUI SQLite database in DB Browser for SQLite
:: Double-click or run from command line

SET "ROOT=%~dp0"
SET "DB=%ROOT%data\openwebui_data\webui.db"
SET "BROWSER=%ROOT%apps\db-browser\DB Browser for SQLite.exe"

if not exist "%BROWSER%" (
    echo DB Browser for SQLite not found.
    echo Expected: apps\db-browser\DB Browser for SQLite.exe
    pause
    exit /b 1
)

if not exist "%DB%" (
    echo Database not found at: %DB%
    echo Start the project first to create it.
    pause
    exit /b 1
)

echo Opening: %DB%
start "" "%BROWSER%" "%DB%"
