@echo off
cd /d "%~dp0"

echo ================================
echo   Ship It - save progress
echo ================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto NOREPO

set "MSG=%*"
if not "%MSG%"=="" goto COMMIT

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"`) do set "STAMP=%%i"
set "MSG=save %STAMP%"

:COMMIT
echo Commit message: %MSG%
git add -A
git commit -m "%MSG%"
if errorlevel 1 goto NOCHANGES

git push
if errorlevel 1 goto NOPUSH
echo.
echo [+] Saved locally and pushed to GitHub.
goto END

:NOCHANGES
echo.
echo [i] Nothing changed - nothing to save.
goto END

:NOPUSH
echo.
echo [!] Saved locally, but push failed. Check your internet connection.
goto END

:NOREPO
echo [!] No git repository here.
echo     See section 3 of README.md.

:END
echo.
echo (tip: you can pass your own message - save.bat phase 2 done)
pause
