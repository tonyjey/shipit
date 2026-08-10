@echo off
cd /d "%~dp0"
setlocal enabledelayedexpansion

echo ================================
echo   Ship It - project check
echo ================================
echo.

if not exist godot_path.txt goto ASK
goto RUN

:ASK
echo First run only: point me to your Godot executable.
echo Just drag Godot_v4.7...exe into this window and press Enter.
echo.
set "GP="
set /p GP="Path to Godot: "
if "!GP!"=="" (
    echo Empty input. Run check.bat again.
    pause
    exit /b 1
)
>godot_path.txt echo !GP!
echo.

:RUN
set /p GODOT=<godot_path.txt
set "GODOT=!GODOT:"=!"

rem godot_path.txt may contain a FOLDER instead of the .exe - resolve it.
if not exist "!GODOT!\" goto HAVE_EXE
set "FOUND="
for %%F in ("!GODOT!\*console*.exe") do set "FOUND=%%~fF"
if not defined FOUND for %%F in ("!GODOT!\Godot*.exe") do set "FOUND=%%~fF"
if not defined FOUND for %%F in ("!GODOT!\godot*.exe") do set "FOUND=%%~fF"
if not defined FOUND (
    echo [x] godot_path.txt points to a folder with no Godot executable inside:
    echo     !GODOT!
    echo     Put the full path to Godot_v4.7...exe into godot_path.txt
    pause
    exit /b 1
)
set "GODOT=!FOUND!"
>godot_path.txt echo !GODOT!
echo [i] Resolved Godot executable:
echo     !GODOT!
echo.

:HAVE_EXE
if not exist "!GODOT!" (
    echo [!] Godot not found at: !GODOT!
    echo     Delete godot_path.txt and run check.bat again.
    pause
    exit /b 1
)

echo Step 1/2 - importing and parsing scripts...
"!GODOT!" --headless --path "%CD%" --import > check_log.txt 2>&1

echo Step 2/2 - test launch...
"!GODOT!" --headless --path "%CD%" --quit-after 30 >> check_log.txt 2>&1

echo.
echo -------- PROBLEMS FOUND --------
findstr /i /n /c:"SCRIPT ERROR" /c:"Parse Error" /c:"ERROR:" /c:"Cannot infer" /c:"Invalid" /c:"not found" check_log.txt
if errorlevel 1 echo Nothing found. The project builds cleanly.
echo --------------------------------
echo.
echo Full log: check_log.txt
echo.
pause
