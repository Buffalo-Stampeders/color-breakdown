# Color Breakdown

A small app that lists every color in an image with its hex code, a swatch,
and how much of the image it covers.

## Download

| Platform | Download | |
|---|---|---|
| **Windows 10/11** | [ColorBreakdown-windows.zip](https://github.com/Buffalo-Stampeders/color-breakdown/releases/latest/download/ColorBreakdown-windows.zip) | Unzip, run `install.bat`. Adds it to the Start Menu and Settings → Apps |
| Windows, no install | [ColorBreakdown.exe](https://github.com/Buffalo-Stampeders/color-breakdown/releases/latest/download/ColorBreakdown.exe) | Single file, run it from anywhere |
| **macOS 13+ (Apple Silicon)** | [ColorBreakdown-mac.zip](https://github.com/Buffalo-Stampeders/color-breakdown/releases/latest/download/ColorBreakdown-mac.zip) | Unzip, drag the app into Applications |

Older versions are on the [Releases page](https://github.com/Buffalo-Stampeders/color-breakdown/releases).

Both apps check this repo's Releases when they start and offer the new
version when there is one (Mac: **Color Breakdown → Check for Updates…**;
Windows: **Check for Updates** button). They open the download page; they
never replace themselves.

Neither download is signed with a paid developer certificate, so the first
launch needs one extra step:

- **Windows:** if "Windows protected your PC" appears, click
  **More info → Run anyway**.
- **Mac:** if macOS says it can't verify the app, open
  **System Settings → Privacy & Security**, scroll down and click
  **Open Anyway** next to Color Breakdown. (On macOS 13–14 you can instead
  right-click the app → **Open**.)

## Building it yourself

- **macOS (Apple Silicon):** native SwiftUI app — this folder, instructions below.
- **Windows:** see the `windows/` folder and `windows/README-Windows.md`.
- **Automatic builds:** every push to `main` builds both apps on GitHub
  (Actions tab → latest run → *Artifacts*). Publishing a new version is
  covered in [RELEASING.md](RELEASING.md).

## Build and install on a Mac

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
3. The app is built and installed into `/Applications` (or `~/Applications`
   if `/Applications` isn't writable), so it shows up in Launchpad, Spotlight
   and the Applications folder. Re-running the script quits a running copy
   and upgrades it.

   `./build.sh --no-install` only builds `ColorBreakdown.app` in this folder.

Because the app is built on your own Mac and ad-hoc signed, it runs without any
Gatekeeper warning. (Copied to another Mac it needs the one-time
**Open Anyway** step above.)

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
