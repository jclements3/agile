@echo off
rem agile.cmd -- runs agile.ps1 from anywhere: agile status, agile paste Alpha, agile lint -Reply -Clip
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0agile.ps1" %*
exit /b %ERRORLEVEL%
