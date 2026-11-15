#!/bin/sh
# Generates Support/Sphere.icns from scripts/draw-icon.swift.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ICONSET="$TMP/Sphere.iconset"
mkdir -p "$ICONSET"

swift "$ROOT/scripts/draw-icon.swift" "$TMP/icon_1024.png" >/dev/null

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$TMP/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$TMP/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

sips -z 1024 1024 "$TMP/icon_1024.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ROOT/Support/Sphere.icns"
echo "wrote $ROOT/Support/Sphere.icns"
