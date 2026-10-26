# Color Breakdown — Windows version

Same features as the Mac app: open any image, see every color as a swatch
with its hex code, percentage and pixel count; click a row to copy the hex;
Exact / Fine / Medium / Coarse grouping; minimum-coverage filter (10% by
default); CSV export.

## Option A — build a standalone .exe (recommended)

1. Install Python 3 from https://www.python.org/downloads/windows/ and tick
   **"Add python.exe to PATH"** during setup.
2. Double-click `build-windows.bat`. It installs the libraries it needs and
   produces `dist\ColorBreakdown.exe` (about 30–40 MB, fully self-contained).
3. Move `ColorBreakdown.exe` wherever you like and run it. The first launch of
   an unsigned .exe may show a SmartScreen prompt — click *More info → Run
   anyway* once.

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
