#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_ROOT="${1:-$ROOT/Assets.xcassets}"
ICON_SET="$ASSET_ROOT/AppIcon.appiconset"

rm -rf "$ICON_SET"
mkdir -p "$ICON_SET"

cp "$ROOT/app-icon-starorbit-glass-1024.png" "$ICON_SET/AppIcon-Light.png"
cp "$ROOT/app-icon-starorbit-glass-dark-1024.png" "$ICON_SET/AppIcon-Dark.png"
cp "$ROOT/app-icon-starorbit-glass-tinted-1024.png" "$ICON_SET/AppIcon-Tinted.png"

cat > "$ICON_SET/Contents.json" <<'JSON'
{
  "images": [
    {
      "filename": "AppIcon-Light.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    },
    {
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "dark"
        }
      ],
      "filename": "AppIcon-Dark.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    },
    {
      "appearances": [
        {
          "appearance": "luminosity",
          "value": "tinted"
        }
      ],
      "filename": "AppIcon-Tinted.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
JSON

echo "Prepared Liquid Glass AppIcon asset at $ICON_SET"
