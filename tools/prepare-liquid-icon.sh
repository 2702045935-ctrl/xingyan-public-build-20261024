#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ROOT="${1:-$ROOT}"
ICON_SET="$PACKAGE_ROOT/AppIcon.icon"

rm -rf "$ICON_SET"
python3 "$ROOT/tools/build-liquid-icon-package.py" \
  --output "$PACKAGE_ROOT"

echo "Prepared Liquid Glass AppIcon asset at $ICON_SET"
