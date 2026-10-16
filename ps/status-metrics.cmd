@echo off
rem status-metrics.cmd -- runs status-metrics.ps1 from anywhere: status-metrics collect --config metrics.json --history history.jsonl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0status-metrics.ps1" %*
exit /b %ERRORLEVEL%
