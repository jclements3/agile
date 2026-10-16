@echo off
rem gitlab-ci.cmd -- runs gitlab-ci.ps1 from anywhere: gitlab-ci.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0gitlab-ci.ps1" %*
exit /b %ERRORLEVEL%
