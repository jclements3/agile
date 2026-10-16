@echo off
rem cards.cmd -- runs cards.ps1 from anywhere
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cards.ps1" %*
exit /b %ERRORLEVEL%
