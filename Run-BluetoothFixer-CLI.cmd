@echo off
:: Windows Bluetooth Fixer - command-line launcher (elevated console, diagnose then offer recommended fixes)
setlocal
set "ROOT=%~dp0"
set "SCRIPT=%ROOT%src\BluetoothFixer.CLI.ps1"
if not exist "%SCRIPT%" (
    echo Could not find "%SCRIPT%". Keep this .cmd next to the src folder.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%SCRIPT%\" -Fix Recommended -Report'"
endlocal
