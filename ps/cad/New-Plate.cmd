@echo off
rem New-Plate.cmd -- STL in, ISO 128 drawing plate (SVG) out: New-Plate -Stl part.stl -Dimensions -Title "Housing"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-Plate.ps1" %*
exit /b %ERRORLEVEL%
