#!/bin/bash
# Compile et empaquette MacSystemMonitor en une vraie app macOS (.app).
set -e
cd "$(dirname "$0")"

APP_NAME="Moniteur Système"
BUNDLE="$APP_NAME.app"
BIN="MacSystemMonitor"

echo "▶︎ Compilation (release)…"
swift build -c release

echo "▶︎ Création du bundle $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp ".build/release/$BIN" "$BUNDLE/Contents/MacOS/$BIN"

# Icône (générée par make_icon.swift → AppIcon.icns)
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>fr.sensaas.macsystemmonitor</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>$BIN</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <!-- App d'arrière-plan : pas d'icône dans le Dock -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Signature locale (ad-hoc) pour éviter les avertissements Gatekeeper au lancement.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✅ Terminé : $(pwd)/$BUNDLE"
echo "   Lance-la avec :  open \"$BUNDLE\""
