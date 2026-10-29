@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if errorlevel 1 (
  echo Falha na instalacao.
  pause
  exit /b 1
)
echo Instalacao concluida. Abra um novo terminal para usar gpt-profile.
pause
