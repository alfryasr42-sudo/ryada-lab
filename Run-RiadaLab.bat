@echo off
chcp 65001 >nul
title Riada Lab
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\launcher.ps1" -Mode Run
echo.
pause
