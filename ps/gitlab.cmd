@echo off
rem gitlab.cmd -- runs gitlab.ps1 from anywhere: gitlab --local DIR issue list, gitlab help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gitlab.ps1" %*
exit /b %ERRORLEVEL%
