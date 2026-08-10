@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ================================
echo   Ship It - what changed
echo ================================
echo.
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto NOREPO
echo --- files ---
echo   M = changed, ?? = new, D = deleted
echo.
git status --short
echo.
echo --- lines changed in tracked files ---
git diff --stat
echo.
echo --- last 5 saves ---
git log --oneline -5
echo.
echo Nothing above is sent anywhere. To save: run save.bat
goto END
:NOREPO
echo [!] No git repository here.
:END
echo.
pause
