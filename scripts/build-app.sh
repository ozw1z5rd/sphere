#!/bin/sh
# Build Sphere.app as a real macOS application bundle in dist/.
#
# Usage:
#   scripts/build-app.sh [debug|release] [--open]
#
# The bundle is ad-hoc code signed so macOS keeps TCC permissions (Screen
# Recording) attached to a stable bundle identity.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG="${1:-release}"
OPEN_FLAG="${2:-}"

cd "$ROOT"

echo "Building Sphere ($CONFIG)…"
swift build -c "$CONFIG" --product Sphere

BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
APP="$ROOT/dist/Sphere.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Sphere" "$APP/Contents/MacOS/Sphere"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$ROOT/Support/Sphere.icns" ]; then
    cp "$ROOT/Support/Sphere.icns" "$APP/Contents/Resources/Sphere.icns"
fi

if [ -f "$ROOT/Sources/SphereApp/Resources/CompanyLogo.png" ]; then
    cp "$ROOT/Sources/SphereApp/Resources/CompanyLogo.png" "$APP/Contents/Resources/CompanyLogo.png"
fi

for lproj in "$ROOT/Sources/SphereApp/Resources"/*.lproj; do
    [ -e "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
done

for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Ensure our own freshly built bundle is not quarantined.
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc signature. No Developer ID is required to run locally.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
    || codesign --force --sign - "$APP/Contents/MacOS/Sphere"

if codesign --verify --verbose "$APP" 2>/dev/null; then
    echo "Code signature: valid (ad-hoc)"
else
    echo "warning: codesign verification failed" >&2
fi

echo "Built: $APP"

if [ "$OPEN_FLAG" = "--open" ]; then
    echo "Launching Sphere…"
    open "$APP"
fi
