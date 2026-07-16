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
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run with: open $APP"
