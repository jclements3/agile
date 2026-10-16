@echo off
rem md2docs.cmd -- runs md2docs.ps1 from anywhere: md2docs docs, md2docs docs -Word -Title "Halberd HWS Model"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0md2docs.ps1" %*
exit /b %ERRORLEVEL%
