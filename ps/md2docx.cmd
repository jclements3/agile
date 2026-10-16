@echo off
rem md2docx.cmd -- runs md2docx.ps1 from anywhere: md2docx memo.md, md2docx memo.md -Default "CUI" -Memo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0md2docx.ps1" %*
exit /b %ERRORLEVEL%
