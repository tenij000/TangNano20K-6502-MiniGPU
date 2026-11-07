@echo off
title MiniGPU SD-Kaart & SDRAM-Disk Uploader Studio (Tang Nano 20K)
cd /d "%~dp0"
if exist "E:\hardware\.venv\Scripts\pythonw.exe" (
    start "" "E:\hardware\.venv\Scripts\pythonw.exe" "%~dp0sd_gui.py"
) else (
    start "" pythonw "%~dp0sd_gui.py"
)
