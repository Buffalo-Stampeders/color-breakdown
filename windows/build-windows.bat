@echo off
REM Builds a standalone ColorBreakdown.exe (no Python needed to run it).
REM Requires Python 3.9+ from python.org with "Add to PATH" ticked.
setlocal
cd /d "%~dp0"

echo Installing build dependencies...
python -m pip install --quiet --upgrade pillow numpy pyinstaller
if errorlevel 1 goto :fail

echo Building...
python -m PyInstaller --noconfirm --clean --onefile --windowed ^
  --name ColorBreakdown ^
  --icon AppIcon.ico ^
  --add-data "AppIcon.png;." ^
  color_breakdown.py
if errorlevel 1 goto :fail

echo.
echo Done:  dist\ColorBreakdown.exe
echo You can move that .exe anywhere (Desktop, Program Files, a USB stick).
pause
exit /b 0

:fail
echo.
echo Build failed - see messages above.
pause
exit /b 1
