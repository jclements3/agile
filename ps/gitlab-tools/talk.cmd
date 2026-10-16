@echo off
rem talk.cmd -- runs talk.ps1 from anywhere: talk.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0talk.ps1" %*
exit /b %ERRORLEVEL%
