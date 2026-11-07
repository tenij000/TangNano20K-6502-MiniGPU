@echo off
title MiniGPU Paint Studio (MiniGPU-BASIC 1.1 Edition)
cd /d "%~dp0"
if exist "E:\hardware\.venv\Scripts\pythonw.exe" (
    start "" "E:\hardware\.venv\Scripts\pythonw.exe" "%~dp0gpu_paint.py"
) else (
    python "%~dp0gpu_paint.py"
)
