@echo off
chcp 65001 >nul
title Riada Lab - Build APK
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\launcher.ps1" -Mode Build
echo.
pause
