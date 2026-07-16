#!/bin/zsh
# Builds a release binary and wraps it into SkillManager.app (in ./dist).
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

# Rebuild the app icon from source if the toolchain is available.
if command -v iconutil >/dev/null 2>&1; then
    swift Tools/IconGen.swift Tools/build/AppIcon.iconset >/dev/null
    iconutil -c icns Tools/build/AppIcon.iconset -o Resources/AppIcon.icns
fi

APP=dist/SkillManager.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/SkillManager "$APP/Contents/MacOS/SkillManager"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SPM resource bundles (localization tables) must ship inside the app.
for bundle in .build/release/*.bundle; do
    [[ -d "$bundle" ]] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Skill Manager</string>
    <key>CFBundleDisplayName</key><string>Skill Manager</string>
    <key>CFBundleIdentifier</key><string>local.skillmanager</string>
    <key>CFBundleExecutable</key><string>SkillManager</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1.4</string>
    <key>CFBundleShortVersionString</key><string>1.4</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Set CODESIGN_IDENTITY to a "Developer ID Application: …" identity for
# distribution builds; without it we fall back to ad-hoc signing.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
        --sign "$CODESIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "Built $APP"
echo "Run with: open $APP"
