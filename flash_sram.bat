@echo off
cd /d "%~dp0"
echo ==============================================================
echo   Tang Nano 20K - DONDERDAG MiniGPU-BASIC Flashen (SRAM)
echo ==============================================================
echo.
"C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe" --device GW2AR-18C --run 2 --fsFile "%~dp0impl\pnr\MiniGPU_BASIC.fs"
echo.
if %ERRORLEVEL% equ 0 (
    echo [SUCCES] DONDERDAG MiniGPU-BASIC draait nu op de Tang Nano 20K!
) else (
    echo [FOUT] Flashen mislukt. Controleer de USB-kabelverbinding.
)
pause
