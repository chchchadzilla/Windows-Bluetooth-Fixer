@echo off
:: Windows Bluetooth Fixer - double-click launcher (GUI, asks for administrator rights)
setlocal
set "ROOT=%~dp0"
set "SCRIPT=%ROOT%src\BluetoothFixer.GUI.ps1"
if not exist "%SCRIPT%" (
    echo Could not find "%SCRIPT%". Keep this .cmd next to the src folder.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%SCRIPT%\" -AutoDiagnose'"
endlocal
