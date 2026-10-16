@echo off
rem invite.cmd -- runs invite.ps1 from anywhere: invite -Dry, invite -Until 2027-09-30 -Open
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0invite.ps1" %*
exit /b %ERRORLEVEL%
