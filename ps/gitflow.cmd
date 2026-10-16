@echo off
rem gitflow.cmd -- runs gitflow.ps1 from anywhere: gitflow.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gitflow.ps1" %*
exit /b %ERRORLEVEL%
