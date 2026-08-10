@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0.."
set /p GODOT=<godot_path.txt
set "GODOT=!GODOT:"=!"
"!GODOT!" --path "%CD%" res://rig_debug.tscn --resolution 1280x720 --position 120,120 --quit-after 1500
