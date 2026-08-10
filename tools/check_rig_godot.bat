@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0.."
set "LOG=tools\godot_rig_log.txt"

set /p GODOT=<godot_path.txt
set "GODOT=!GODOT:"=!"
if not exist "!GODOT!\" goto HAVE_EXE
set "FOUND="
for %%F in ("!GODOT!\*console*.exe") do set "FOUND=%%~fF"
if not defined FOUND for %%F in ("!GODOT!\Godot*.exe") do set "FOUND=%%~fF"
if not defined FOUND for %%F in ("!GODOT!\godot*.exe") do set "FOUND=%%~fF"
if not defined FOUND (
    echo [x] no Godot executable in !GODOT!
    echo no godot exe>"%LOG%"
    exit /b 1
)
set "GODOT=!FOUND!"
>godot_path.txt echo !GODOT!
:HAVE_EXE
echo [i] Godot: !GODOT!

echo Step 1/2 - importing assets...
"!GODOT!" --headless --path "%CD%" --import >"%LOG%" 2>&1
echo Step 2/2 - running rig check scene...
"!GODOT!" --headless --path "%CD%" res://rig_debug.tscn --quit-after 120 >>"%LOG%" 2>&1
echo EXITCODE=!errorlevel!>>"%LOG%"
echo Done. Log: %LOG%
