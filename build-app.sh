#!/bin/zsh
# Builds "Just Type It.app" and installs it to ~/Applications.
# Created by Stefano Roman Gunness · MIT License
set -e
cd "$(dirname "$0")"

swift build -c release

APP="build/Just Type It.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/JustTypeIt "$APP/Contents/MacOS/JustTypeIt"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Just Type It</string>
  <key>CFBundleDisplayName</key><string>Just Type It</string>
  <key>CFBundleIdentifier</key><string>com.stefano.justtypeit</string>
  <key>CFBundleExecutable</key><string>JustTypeIt</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.1</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Stefano Roman Gunness. MIT License.</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Just Type It pastes corrected text back into the app you are using.</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Check with Just Type It</string></dict>
      <key>NSMessage</key><string>checkText</string>
      <key>NSPortName</key><string>Just Type It</string>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string><string>public.utf8-plain-text</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable local identity so macOS keeps the Accessibility permission across rebuilds.
./scripts/make-signing-identity.sh >/dev/null
cat > build/entitlements.plist <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.automation.apple-events</key><true/>
</dict></plist>
ENT
codesign --force --options runtime --entitlements build/entitlements.plist \
  --sign "Just Type It Local Signing" --keychain "$HOME/Library/Keychains/justtypeit-signing.keychain-db" \
  --identifier com.stefano.justtypeit "$APP"

pkill -x JustTypeIt 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/"Just Type It.app"
cp -R "$APP" ~/Applications/
rm -rf "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/"Just Type It.app" >/dev/null 2>&1 || true
echo "Installed: ~/Applications/Just Type It.app"
