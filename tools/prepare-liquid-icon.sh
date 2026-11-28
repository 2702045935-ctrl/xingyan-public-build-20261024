#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_ROOT="${1:-$ROOT/Assets.xcassets}"
ICON_SET="$ASSET_ROOT/AppIcon.icon"

rm -rf "$ICON_SET"
python3 "$ROOT/tools/build-liquid-icon-package.py" \
  --output "$ASSET_ROOT"

echo "Prepared Liquid Glass AppIcon asset at $ICON_SET"
