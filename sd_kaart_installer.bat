@echo off
title MiniGPU-BASIC 1.4 - Complete Windows SD-Kaart Installer
cd /d "%~dp0"
start "" pythonw "%~dp0sd_kaart_installer.py"
if errorlevel 1 python "%~dp0sd_kaart_installer.py"
