@echo off
rem pgit.cmd -- runs pgit.ps1 from anywhere: pgit status, pgit add -A, pgit commit -m "message"
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pgit.ps1" %*
exit /b %ERRORLEVEL%
