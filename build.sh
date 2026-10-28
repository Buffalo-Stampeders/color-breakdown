#!/bin/zsh
# Builds ColorBreakdown.app for Apple Silicon Macs and installs it into
# /Applications (or ~/Applications if /Applications isn't writable).
#   ./build.sh               build + install
#   ./build.sh --no-install  build only (leaves ./ColorBreakdown.app)
# Requires Xcode Command Line Tools:  xcode-select --install
set -e
cd "$(dirname "$0")"

APP="ColorBreakdown.app"
BIN="ColorBreakdown"
BUNDLE_ID="com.buffalostampeders.colorbreakdown"

INSTALL=1
[[ "$1" == "--no-install" ]] && INSTALL=0

VERSION=$(sed -n 's/^ *static let version = "\(.*\)".*/\1/p' ColorBreakdown.swift | head -1)
if [[ -z "$VERSION" ]]; then
  echo "Couldn't find AppInfo.version in ColorBreakdown.swift" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling Color Breakdown $VERSION…"
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

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Color Breakdown</string>
    <key>CFBundleDisplayName</key>        <string>Color Breakdown</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>         <string>$BIN</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
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

if (( ! INSTALL )); then
  echo
  echo "Built ./$APP ($VERSION)"
  echo "Run it with:  open \"$APP\""
  exit 0
fi

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Quit a running copy (this or an older build) so it can be replaced.
if pgrep -qf "$APP/Contents/MacOS/$BIN"; then
  echo "Quitting the running copy…"
  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  sleep 1
  pkill -f "$APP/Contents/MacOS/$BIN" 2>/dev/null || true
  sleep 1
fi

echo "Installing into $DEST…"
rm -rf "$DEST/$APP"
ditto "$APP" "$DEST/$APP"

echo
echo "Installed Color Breakdown $VERSION → $DEST/$APP"
echo "Find it in Launchpad, Spotlight or the Applications folder."
