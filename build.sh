#!/bin/zsh
# Builds ColorBreakdown.app for Apple Silicon Macs.
# Requires Xcode Command Line Tools:  xcode-select --install
set -e
cd "$(dirname "$0")"

APP="ColorBreakdown.app"
BIN="ColorBreakdown"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O \
  -swift-version 5 \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  ColorBreakdown.swift \
  -o "$APP/Contents/MacOS/$BIN"

if [[ -f AppIcon.png ]]; then
  echo "Building icon…"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Color Breakdown</string>
    <key>CFBundleDisplayName</key>        <string>Color Breakdown</string>
    <key>CFBundleIdentifier</key>         <string>local.colorbreakdown</string>
    <key>CFBundleExecutable</key>         <string>ColorBreakdown</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSArchitecturePriority</key>     <array><string>arm64</string></array>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>     <string>Image</string>
            <key>CFBundleTypeRole</key>     <string>Viewer</string>
            <key>LSHandlerRank</key>        <string>Alternate</string>
            <key>LSItemContentTypes</key>   <array><string>public.image</string></array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "Signing (ad-hoc)…"
codesign --force --sign - "$APP" >/dev/null

echo
echo "Built ./$APP"
echo "Run it with:  open \"$APP\"   (or drag it into /Applications)"
