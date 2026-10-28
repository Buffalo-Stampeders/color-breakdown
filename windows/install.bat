@echo off
REM Installs Color Breakdown for the current user (no admin rights needed):
REM   program   %LOCALAPPDATA%\Programs\Color Breakdown
REM   shortcut  Start Menu (Desktop optional)
REM   listed in Settings > Apps > Installed apps, where it can be uninstalled
REM Options:  /desktop  also add a Desktop shortcut
REM           /quiet    no prompts
setlocal
set "SRC=%~dp0"
set "DEST=%LOCALAPPDATA%\Programs\Color Breakdown"
set "EXE=%DEST%\ColorBreakdown.exe"
set "UNINST_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ColorBreakdown"
set "QUIET="
set "DESKTOP="
for %%a in (%*) do (
  if /i "%%~a"=="/quiet" set "QUIET=1"
  if /i "%%~a"=="/desktop" set "DESKTOP=1"
)

if not exist "%SRC%ColorBreakdown.exe" (
  echo ColorBreakdown.exe was not found next to install.bat.
  goto :fail
)

echo Installing Color Breakdown...

REM Close a running copy so the .exe can be replaced.
taskkill /im ColorBreakdown.exe /f >nul 2>&1 && ping -n 2 127.0.0.1 >nul

if not exist "%DEST%" mkdir "%DEST%" || goto :fail
copy /y "%SRC%ColorBreakdown.exe" "%DEST%\" >nul || goto :fail
copy /y "%SRC%uninstall.bat" "%DEST%\" >nul || goto :fail

call :shortcut Programs || goto :fail
if not defined DESKTOP if not defined QUIET (
  choice /c YN /m "Also add a Desktop shortcut"
  if not errorlevel 2 set "DESKTOP=1"
)
if defined DESKTOP call :shortcut Desktop

set "VERSION="
for /f "usebackq delims=" %%v in (`powershell -NoProfile -Command "(Get-Item -LiteralPath $env:EXE).VersionInfo.ProductVersion"`) do set "VERSION=%%v"
for %%f in ("%EXE%") do set /a SIZE_KB=%%~zf / 1024

reg add "%UNINST_KEY%" /v DisplayName /d "Color Breakdown" /f >nul || goto :fail
reg add "%UNINST_KEY%" /v DisplayVersion /d "%VERSION%" /f >nul
reg add "%UNINST_KEY%" /v Publisher /d "Buffalo Stampeders" /f >nul
reg add "%UNINST_KEY%" /v DisplayIcon /d "%EXE%" /f >nul
reg add "%UNINST_KEY%" /v InstallLocation /d "%DEST%" /f >nul
reg add "%UNINST_KEY%" /v UninstallString /d "\"%DEST%\uninstall.bat\"" /f >nul
reg add "%UNINST_KEY%" /v QuietUninstallString /d "\"%DEST%\uninstall.bat\" /quiet" /f >nul
reg add "%UNINST_KEY%" /v EstimatedSize /t REG_DWORD /d %SIZE_KB% /f >nul
reg add "%UNINST_KEY%" /v NoModify /t REG_DWORD /d 1 /f >nul
reg add "%UNINST_KEY%" /v NoRepair /t REG_DWORD /d 1 /f >nul

echo.
echo Installed Color Breakdown %VERSION% to "%DEST%"
echo Open it from the Start Menu. Uninstall it from Settings ^> Apps ^> Installed apps.
if not defined QUIET pause
exit /b 0

REM Creates "Color Breakdown.lnk" in a special folder (Programs = Start Menu, or Desktop).
:shortcut
set "SC_FOLDER=%~1"
powershell -NoProfile -Command "$lnk = Join-Path ([Environment]::GetFolderPath($env:SC_FOLDER)) 'Color Breakdown.lnk'; $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = $env:EXE; $s.WorkingDirectory = $env:DEST; $s.IconLocation = $env:EXE + ',0'; $s.Description = 'Color Breakdown'; $s.Save()"
exit /b %errorlevel%

:fail
echo.
echo Installation failed - see messages above.
if not defined QUIET pause
exit /b 1
