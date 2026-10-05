@echo off
rem Double-click to turn every .t64 on the Pocket card's Assets\c64\common into a .prg (runs convert-t64.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0convert-t64.ps1" %*
echo.
pause
