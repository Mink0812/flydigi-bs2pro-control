@echo off
title BS2 Pro - Lights off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bs2pro-control.ps1" -LedOff
if errorlevel 1 pause
exit
