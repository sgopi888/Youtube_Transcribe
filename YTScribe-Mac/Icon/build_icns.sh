#!/bin/bash
# Regenerates Icon/AppIcon.icns from Icon/source.png (see make_icon.swift).
set -euo pipefail
cd "$(dirname "$0")"
swift make_icon.swift source.png master.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s master.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) master.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
