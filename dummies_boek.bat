@echo off
title MiniGPU-BASIC 1.1 Voor Dummies - Live COM-Poort Test Server
cd /d "%~dp0"
if exist "E:\hardware\.venv\Scripts\python.exe" (
    "E:\hardware\.venv\Scripts\python.exe" "%~dp0dummies_server.py"
) else (
    python "%~dp0dummies_server.py"
)
