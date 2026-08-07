#!/bin/bash
# Builds JobScout.app (Apple Silicon release build) into the project root.
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Building release binary (arm64)…"
swift build -c release 2>&1 | tail -2

APP="JobScout.app"
BIN=".build/release/JobScout"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/JobScout"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# App icon: generate once, reuse afterwards.
if [ ! -f scripts/AppIcon.icns ]; then
    echo "▸ Generating app icon…"
    swift scripts/make-icon.swift scripts/icon-1024.png
    ICONSET=scripts/AppIcon.iconset
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for s in 16 32 64 128 256 512; do
        sips -z $s $s scripts/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d scripts/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o scripts/AppIcon.icns
    rm -rf "$ICONSET"
fi
cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS runs it without complaints on this Mac.
codesign --force --deep -s - "$APP" 2>/dev/null

echo "✅ Built $PWD/$APP"
echo "   Open it:  open \"$PWD/$APP\""
