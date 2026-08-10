@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0.."
set "PYTHONIOENCODING=utf-8"
set "LOG=tools\blender_log.txt"

echo ================================
echo   Ship It - build character
echo ================================
echo.

set "BL="
if exist blender_path.txt (
    set /p BL=<blender_path.txt
    set "BL=!BL:"=!"
    if not exist "!BL!" set "BL="
)

if not defined BL for %%P in ("D:\SteamLibrary\steamapps\common\Blender\blender.exe" "C:\SteamLibrary\steamapps\common\Blender\blender.exe" "E:\SteamLibrary\steamapps\common\Blender\blender.exe" "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe") do if not defined BL if exist %%P set "BL=%%~P"
if not defined BL for /f "delims=" %%F in ('where blender 2^>nul') do if not defined BL set "BL=%%F"

if not defined BL (
    echo [x] blender.exe not found. Put full path into blender_path.txt
    echo blender.exe not found>"%LOG%"
    exit /b 1
)

>blender_path.txt echo !BL!
echo [i] Blender: !BL!
echo.
echo Building model + running rig self-test...

"!BL!" --background --python "tools\stylized_character_blender.py" --python "tools\rig_selftest.py" >"%LOG%" 2>&1
echo EXITCODE=!errorlevel!>>"%LOG%"

echo.
if exist "models\character.glb" (echo [ok] models\character.glb created.) else (echo [x] character.glb NOT created - see %LOG%)
echo Full log: %LOG%
