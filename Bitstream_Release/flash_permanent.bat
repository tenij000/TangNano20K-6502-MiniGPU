@echo off
cd /d "%~dp0"
echo ===================================================================
echo   Tang Nano 20K - MiniGPU-BASIC 1.2 (Permanent in SPI Flash)
echo ===================================================================
echo.

set "PROG=C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe"
if not exist "%PROG%" (
    for /f "delims=" %%F in ('dir /b /s "C:\Gowin\programmer_cli.exe" 2^>nul') do set "PROG=%%F"
)

if not exist "%PROG%" (
    echo [FOUT] Gowin programmer_cli.exe niet gevonden in C:\Gowin.
    echo Gebruik Gowin Programmer GUI en selecteer "%~dp0MiniGPU_BASIC.fs".
    pause
    exit /b 1
)

echo Bezig met wissen en programmeren van extern SPI Flash geheugen...
echo Dit duurt ongeveer 15 tot 20 seconden.
echo.
"%PROG%" --device GW2AR-18C --run 8 --fsFile "%~dp0MiniGPU_BASIC.fs"
echo.
if %ERRORLEVEL% equ 0 (
    echo [SUCCES] MiniGPU-BASIC 1.2 is permanent opgeslagen in de SPI Flash!
    echo Bezig met herladen vanuit Flash...
    "%PROG%" --device GW2AR-18C --run 1
    echo De Tang Nano 20K start nu altijd zelfstandig op in MiniGPU-BASIC!
) else (
    echo [FOUT] Flashen mislukt. Controleer de USB-kabelverbinding.
)
echo.
pause
