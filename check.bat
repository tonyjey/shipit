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
