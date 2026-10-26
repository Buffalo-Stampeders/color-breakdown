# Color Breakdown

A small app that lists every color in an image with its hex code, a swatch,
and how much of the image it covers.

- **macOS (Apple Silicon):** native SwiftUI app — this folder, instructions below.
- **Windows:** see the `windows/` folder and `windows/README-Windows.md`.

## Build (one time)

1. Make sure the Xcode Command Line Tools are installed:
   ```
   xcode-select --install
   ```
2. In Terminal:
   ```
   cd /path/to/ColorBreakdown
   chmod +x build.sh
   ./build.sh
   ```
3. `ColorBreakdown.app` appears in the same folder. Double-click it or drag it
   into `/Applications`.

Because the app is built on your own Mac and ad-hoc signed, it runs without any
Gatekeeper warning. (If you copy it to another Mac you'd have to right-click →
Open the first time.)

## Using it

- **Open an image** – drag any image file onto the window, press ⌘O, or
  right-click an image in Finder → Open With → Color Breakdown.
  Supports PNG, JPEG, HEIC, TIFF, GIF, BMP, WebP, PSD, and anything else
  macOS can read (raster formats only — not SVG or PDF).
- **Color list** – sorted most common → least common, each row showing the
  swatch, hex code, percentage of the image, and pixel count.
- **Click a row** (or right-click) to copy the hex code.
- **Filter** – type part of a hex code in the search box.
- **Grouping** – *Exact* lists every distinct RGB value (a photo can have
  hundreds of thousands). *Fine / Medium / Coarse* merge near-identical shades
  so you get a shorter palette-style list; the hex shown is the average of the
  merged pixels.
- **Minimum coverage** – colors covering less than 10% of the image are
  disregarded by default. Use the stepper in the sidebar to raise or lower the
  threshold (0% shows everything).
- **Export CSV** (⌘E) – writes hex, R, G, B, pixel count, and percent for every
  color that meets the minimum coverage.

`AppIcon.png` is the Dock/Finder icon; `build.sh` converts it into the
`.icns` the app bundle needs, so just keep it next to the script.

Fully transparent pixels are ignored; partially transparent pixels are
counted at their true (un-premultiplied) color. Images larger than 4096 px on
the long side are scaled down before counting to keep things fast.
