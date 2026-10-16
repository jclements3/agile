@echo off
rem townhall.cmd -- runs townhall.ps1 from anywhere
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0townhall.ps1" %*
exit /b %ERRORLEVEL%
