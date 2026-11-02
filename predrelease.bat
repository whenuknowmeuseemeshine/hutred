@echo off
chcp 65001 >nul
rem Предрелиз Hutred: собирает свежий код из этой папки и запускает его.
rem Ключи облака лежат в hutred.env.json рядом (его не выкладываем никуда).
cd /d "%~dp0"
if not exist hutred.env.json (
  echo Нет файла hutred.env.json — открой hutred.env.example.json, впиши ключи и сохрани как hutred.env.json
  pause
  exit /b 1
)
echo Закрываю Hutred, если открыт...
taskkill /im hutred.exe /f >nul 2>&1
echo Собираю предрелиз (первый раз несколько минут, потом быстрее)...
call flutter pub get || goto fail
call flutter build windows --release --dart-define-from-file=hutred.env.json || goto fail
start "" "build\windows\x64\runner\Release\hutred.exe"
exit /b 0
:fail
echo.
echo Сборка не удалась — пришли скрин этого окна.
pause
