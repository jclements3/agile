@echo off
rem kickoff.cmd -- runs kickoff.ps1 from anywhere: kickoff.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kickoff.ps1" %*
exit /b %ERRORLEVEL%
