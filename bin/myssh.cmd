@echo off
setlocal
set "SCRIPT=%~dp0myssh.ps1"
where pwsh >nul 2>nul
if errorlevel 1 (
  echo [myssh] 未找到 pwsh，请先安装 PowerShell 7+。
  exit /b 1
)
pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
