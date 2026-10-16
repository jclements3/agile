@echo off
rem pvi.cmd -- runs pvi.ps1 from anywhere: pvi FILE..., pvi -Ex FILE, pvi -Script CMDS FILE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0pvi.ps1" %*
exit /b %ERRORLEVEL%
