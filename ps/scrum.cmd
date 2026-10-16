@echo off
rem scrum.cmd -- runs scrum.ps1 from anywhere: scrum -f scrum.txt sprint, scrum velocity --last 4, scrum help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scrum.ps1" %*
exit /b %ERRORLEVEL%
