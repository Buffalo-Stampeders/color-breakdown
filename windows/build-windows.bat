@echo off
REM Builds dist\ with ColorBreakdown.exe (no Python needed to run it),
REM install.bat and uninstall.bat, then offers to install on this PC.
REM Requires Python 3.9+ from python.org with "Add to PATH" ticked.
REM   build-windows.bat --ci   build only, no prompts (used by GitHub Actions)
setlocal
cd /d "%~dp0"
set "CI_MODE="
if /i "%~1"=="--ci" set "CI_MODE=1"

echo Installing build dependencies...
python -m pip install --quiet --upgrade pillow numpy pyinstaller
if errorlevel 1 goto :fail

set "VERSION="
for /f "usebackq delims=" %%v in (`python make_version_file.py`) do set "VERSION=%%v"
if not defined VERSION goto :fail

echo Building Color Breakdown %VERSION%...
python -m PyInstaller --noconfirm --clean --onefile --windowed ^
  --name ColorBreakdown ^
  --icon AppIcon.ico ^
  --add-data "AppIcon.png;." ^
  --version-file version_info.txt ^
  color_breakdown.py
if errorlevel 1 goto :fail

copy /y install.bat dist\ >nul || goto :fail
copy /y uninstall.bat dist\ >nul || goto :fail

echo.
echo Done:  dist\ColorBreakdown.exe, dist\install.bat, dist\uninstall.bat
echo To use it on another PC, copy the whole dist folder and run install.bat.
if defined CI_MODE exit /b 0

echo.
choice /c YN /m "Install Color Breakdown on this PC now"
if errorlevel 2 goto :done
call dist\install.bat
exit /b 0

:done
pause
exit /b 0

:fail
echo.
echo Build failed - see messages above.
if not defined CI_MODE pause
exit /b 1
