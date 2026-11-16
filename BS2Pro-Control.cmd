@echo off
title BS2 Pro Control
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bs2pro-control.ps1"
if errorlevel 1 pause
exit
