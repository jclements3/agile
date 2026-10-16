@echo off
rem practice.cmd -- runs practice.ps1 from anywhere: practice, practice 1, practice check 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0practice.ps1" %*
exit /b %ERRORLEVEL%
