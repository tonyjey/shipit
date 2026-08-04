@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ================================
echo   Сохранение прогресса
echo ================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [!] Здесь ещё нет репозитория Git.
    echo     Пройди раздел "Настройка Git" в README.md.
    echo.
    pause
    exit /b 1
)

set "MSG="
set /p MSG="Что изменилось (можно просто Enter): "
if "%MSG%"=="" set "MSG=промежуточное сохранение"

git add -A
git commit -m "%MSG%"
if errorlevel 1 (
    echo.
    echo [i] Изменений не было — сохранять нечего.
    echo.
    pause
    exit /b 0
)

git push
if errorlevel 1 (
    echo.
    echo [!] Локально сохранено, но отправить на GitHub не вышло.
    echo     Проверь интернет и что удалённый репозиторий подключён.
) else (
    echo.
    echo [+] Готово. Прогресс сохранён и отправлен на GitHub.
)

echo.
pause
