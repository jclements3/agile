@echo off
rem drill.cmd -- the memory drill: drill [Team] [-N 12], drill -Sheet [Team], drill -Grade FILE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0drill.ps1" %*
exit /b %ERRORLEVEL%
