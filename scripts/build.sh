#!/usr/bin/env bash
# Builds LidAwake.app (universal when possible) into ./build and optionally installs it.
#   ./scripts/build.sh            -> build/LidAwake.app
#   ./scripts/build.sh --install  -> also copies to /Applications and launches it
#   ./scripts/build.sh --zip      -> also creates dist/LidAwake-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/LidAwake.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

echo "==> Compiling (release)"
BINS=()
for arch in arm64 x86_64; do
  SCRATCH=".build/$arch"
  if swift build -c release --arch "$arch" --scratch-path "$SCRATCH" >/tmp/lidawake-build-$arch.log 2>&1; then
    BINS+=("$(swift build -c release --arch "$arch" --scratch-path "$SCRATCH" --show-bin-path)/LidAwake")
  else
    echo "    (skipping $arch, see /tmp/lidawake-build-$arch.log)"
  fi
done
[ ${#BINS[@]} -gt 0 ] || { echo "build failed"; cat /tmp/lidawake-build-arm64.log; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/LidAwake"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> Generating AppIcon.icns"
  ICONSET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$ICONSET"
  [ -f Resources/AppIcon.png ] || swift scripts/make-icon.swift Resources/AppIcon.png
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing"
codesign --force --deep --options runtime --sign - "$APP"
lipo -info "$APP/Contents/MacOS/LidAwake"

for arg in "$@"; do
  case "$arg" in
    --install)
      echo "==> Installing to /Applications"
      pkill -x LidAwake 2>/dev/null && sleep 1 || true
      rm -rf /Applications/LidAwake.app
      cp -R "$APP" /Applications/
      open /Applications/LidAwake.app
      ;;
    --zip)
      mkdir -p dist
      ditto -c -k --keepParent "$APP" "dist/LidAwake-$VERSION.zip"
      echo "==> dist/LidAwake-$VERSION.zip"
      ;;
  esac
done
echo "Done."
