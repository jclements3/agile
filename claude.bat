@echo off
REM Launches Claude Code in WSL, rooted at this directory.
wsl --cd "%~dp0" -e bash -lc "exec claude"
