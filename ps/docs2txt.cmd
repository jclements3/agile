@echo off
rem docs2txt.cmd -- runs docs2txt.ps1 from anywhere: docs2txt report.docx, docs2txt grep -i radar *.docx *.pdf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0docs2txt.ps1" %*
exit /b %ERRORLEVEL%
