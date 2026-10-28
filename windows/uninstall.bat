@echo off
REM Removes Color Breakdown installed by install.bat: shortcuts, the
REM Settings > Apps entry and the program folder.
REM Options:  /quiet  no prompts
setlocal
set "DEST=%LOCALAPPDATA%\Programs\Color Breakdown"
set "QUIET="
if /i "%~1"=="/quiet" set "QUIET=1"

if not defined QUIET (
  choice /c YN /m "Remove Color Breakdown from this PC"
  if errorlevel 2 exit /b 1
)

taskkill /im ColorBreakdown.exe /f >nul 2>&1 && ping -n 2 127.0.0.1 >nul

powershell -NoProfile -Command "foreach ($f in 'Programs', 'Desktop') { Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath($f)) 'Color Breakdown.lnk') -ErrorAction SilentlyContinue }"
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ColorBreakdown" /f >nul 2>&1

echo Color Breakdown has been removed.
if not defined QUIET pause

REM Delete the program folder last. It contains this script, so (goto) first
REM ends the script and the rest of the line runs after cmd stops reading it.
cd /d "%TEMP%"
(goto) 2>nul & rmdir /s /q "%DEST%"
