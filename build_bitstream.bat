@echo off
cd /d "%~dp0"
set "PYEXE=python"
if exist "E:\hardware\.venv\Scripts\python.exe" set "PYEXE=E:\hardware\.venv\Scripts\python.exe"

echo ==============================================================
echo   MiniGPU-BASIC 1.2 - Bitstream Bouwen (Gowin EDA)
echo ==============================================================
echo.
echo [1/3] Hardware Sprites, Tileset en Wereldkaart genereren...
"%PYEXE%" build_assets.py
if errorlevel 1 goto :err

echo.
echo [2/3] Eigen MiniGPU-BASIC 1.2 ROM assembleren...
"%PYEXE%" build_minigpu_basic_rom.py
if errorlevel 1 goto :err

echo.
echo [3/3] Gowin FPGA Synthese en Place-and-Route uitvoeren...
"C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe" build.tcl
if errorlevel 1 goto :err

echo.
echo [SUCCES] Bitstream staat klaar in: impl\pnr\MiniGPU_BASIC.fs
pause
exit /b 0

:err
echo.
echo [FOUT] Er ging iets mis tijdens het bouwen.
pause
exit /b 1
