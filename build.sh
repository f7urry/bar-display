#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=BarDisplay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BarDisplay "$APP/Contents/MacOS/"
cp Sources/BarDisplay/Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
