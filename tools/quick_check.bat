@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0.."
set "LOG=tools\quick_check_log.txt"
set /p GODOT=<godot_path.txt
set "GODOT=!GODOT:"=!"
"!GODOT!" --headless --path "%CD%" --import >"%LOG%" 2>&1
"!GODOT!" --headless --path "%CD%" --quit-after 60 >>"%LOG%" 2>&1
echo EXITCODE=!errorlevel!>>"%LOG%"
