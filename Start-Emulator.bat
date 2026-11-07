@echo off
chcp 65001 >nul
title Riada Android Emulator
set ANDROID_HOME=D:\Android\Sdk
set ANDROID_SDK_ROOT=D:\Android\Sdk
set ANDROID_AVD_HOME=D:\Android\Avd
start "" "D:\Android\Sdk\emulator\emulator.exe" -avd RiadaPhone -gpu auto
exit
