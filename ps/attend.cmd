@echo off
rem attend.cmd -- runs attend.ps1 from anywhere: attend, attend -Paste -Team Alpha, attend post -Clip
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0attend.ps1" %*
exit /b %ERRORLEVEL%
