# Color Breakdown — Windows version

Same features as the Mac app: open any image, see every color as a swatch
with its hex code, percentage and pixel count; click a row to copy the hex;
Exact / Fine / Medium / Coarse grouping; minimum-coverage filter (10% by
default); CSV export.

The easiest way to get it is the ready-made download in the main
[README](../README.md#download). Unzip `ColorBreakdown-windows.zip` and run
`install.bat`.

## Installing

`install.bat` installs for the current user only, so no admin rights are needed:

- copies the app to `%LOCALAPPDATA%\Programs\Color Breakdown`
- adds **Color Breakdown** to the Start Menu, and asks whether to add a
  Desktop shortcut too
- lists it in **Settings → Apps → Installed apps**, where it can be
  uninstalled (or run `uninstall.bat`)

Running `install.bat` from a newer version upgrades in place. Options:
`/desktop` (add the Desktop shortcut without asking), `/quiet` (no prompts).

The first launch of the unsigned .exe may show a SmartScreen prompt. Click
*More info → Run anyway* once.

## Updates

The app checks GitHub for a newer release each time it starts, and the
**Check for Updates** button checks on demand. If there is one, it offers to
open the download page.

## Option A — build the .exe yourself

1. Install Python 3 from https://www.python.org/downloads/windows/ and tick
   **"Add python.exe to PATH"** during setup.
2. Double-click `build-windows.bat`. It installs the libraries it needs and
   produces a `dist\` folder with `ColorBreakdown.exe` (about 30 MB, fully
   self-contained, version number in its Properties), `install.bat` and
   `uninstall.bat`.
3. It then asks whether to install on this PC. To install on another PC,
   copy the whole `dist\` folder there and run `install.bat`.

## Option B — run from source

```
pip install pillow numpy
python color_breakdown.py
```

Optional: `pip install tkinterdnd2` enables drag-and-drop onto the window
(the Open button and Ctrl+O always work without it).

## Keyboard

- **Ctrl+O** open image · **Ctrl+E** export CSV · click a row to copy its hex

## Notes

- Opens PNG, JPEG, GIF, BMP, TIFF, WebP, ICO, PSD. For HEIC/HEIF (iPhone
  photos) also `pip install pillow-heif` before building.
- Fully transparent pixels are ignored. Images over 4096 px on the long side
  are scaled down before counting.
- `color_breakdown.py` also runs unchanged on macOS and Linux if you ever want
  one codebase for everything.
