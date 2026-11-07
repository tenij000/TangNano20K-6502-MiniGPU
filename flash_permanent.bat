@echo off
cd /d "%~dp0"
echo ===================================================================
echo   Tang Nano 20K - DONDERDAG MiniGPU-BASIC (Permanent in SPI Flash)
echo ===================================================================
echo.
echo Bezig met wissen en programmeren van extern SPI Flash geheugen...
echo Dit duurt ongeveer 10 tot 20 seconden.
echo.
"C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe" --device GW2AR-18C --run 8 --fsFile "%~dp0impl\pnr\MiniGPU_BASIC.fs"
echo.
if %ERRORLEVEL% equ 0 (
    echo [SUCCES] MiniGPU-BASIC is permanent opgeslagen in de SPI Flash!
    echo Bezig met herladen vanuit Flash...
    "C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe" --device GW2AR-18C --run 1
    echo De Tang Nano 20K start nu altijd zelfstandig op in MiniGPU-BASIC!
) else (
    echo [FOUT] Flashen mislukt. Controleer de USB-kabelverbinding.
)
echo.
pause
