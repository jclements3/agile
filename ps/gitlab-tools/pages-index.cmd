@echo off
rem pages-index.cmd -- runs pages-index.ps1 from anywhere: pages-index.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pages-index.ps1" %*
exit /b %ERRORLEVEL%
