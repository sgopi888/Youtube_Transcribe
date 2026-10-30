#!/bin/bash
# Builds build/YTScribe.app (ad-hoc signed, for personal use on this Mac).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/YTScribe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/YTScribe" "$APP/Contents/MacOS/YTScribe"
mkdir -p "$APP/Contents/Resources" && cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Audio tab tools: yt-dlp (official release in vendor/) and a Node runtime for YouTube's JS challenge.
# ffmpeg is NOT bundled yet; the app falls back to Homebrew's.
cp vendor/yt-dlp "$APP/Contents/Resources/yt-dlp"
cp "$(command -v node)" "$APP/Contents/Resources/node"
cp scripts/setup_roformer.sh "$APP/Contents/Resources/setup_roformer.sh"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>YTScribe</string>
<key>CFBundleDisplayName</key><string>YTScribe</string>
<key>CFBundleIdentifier</key><string>com.sgopi.ytscribe</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>YTScribe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
