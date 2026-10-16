@echo off
rem req-recipe.cmd -- runs req-recipe.ps1 from anywhere (Windows PowerShell 5.1; works under Constrained Language Mode)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0req-recipe.ps1" %*
exit /b %ERRORLEVEL%
