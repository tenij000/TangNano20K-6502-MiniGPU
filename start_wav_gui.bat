@echo off
cd /d "%~dp0"
set "PYEXE=python"
if exist "E:\hardware\.venv\Scripts\python.exe" set "PYEXE=E:\hardware\.venv\Scripts\python.exe"
start "" "%PYEXE%" wav_gui.py
