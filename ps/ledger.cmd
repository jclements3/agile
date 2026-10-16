@echo off
rem ledger.cmd -- runs ledger.ps1 from anywhere: ledger -f funding.ledger evm --now 2026-11-30 --complete-file complete-2026-11-30.csv
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ledger.ps1" %*
exit /b %ERRORLEVEL%
