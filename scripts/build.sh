#!/usr/bin/env bash
# Quick local build of "Awake Mac.app" with SwiftPM (ad-hoc signed, universal).
# For signed + notarized releases use scripts/release.sh (Xcode).
#   ./scripts/build.sh            -> "build/Awake Mac.app"
#   ./scripts/build.sh --install  -> also copies to /Applications and launches it
#   ./scripts/build.sh --zip      -> also creates dist/AwakeMac-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer full Xcode's toolchain when installed (no sudo / xcode-select needed).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP="build/Awake Mac.app"
EXE="Awake Mac"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Config/Info.plist)

echo "==> Compiling (release)"
BINS=()
for arch in arm64 x86_64; do
  SCRATCH=".build/$arch"
  if swift build -c release --arch "$arch" --scratch-path "$SCRATCH" >"$SCRATCH.log" 2>&1; then
    BINS+=("$(swift build -c release --arch "$arch" --scratch-path "$SCRATCH" --show-bin-path)/AwakeMac")
  else
    echo "    (skipping $arch, see $SCRATCH.log)"
  fi
done
[ ${#BINS[@]} -gt 0 ] || { echo "build failed"; cat .build/arm64.log; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/$EXE"
cp Config/Info.plist "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/"
cp -R App/*.lproj "$APP/Contents/Resources/"

echo "==> Ad-hoc signing"
codesign --force --deep --options runtime --entitlements Config/AwakeMac.entitlements --sign - "$APP"
lipo -info "$APP/Contents/MacOS/$EXE"

for arg in "$@"; do
  case "$arg" in
    --install)
      echo "==> Installing to /Applications"
      pkill -x "$EXE" 2>/dev/null && sleep 1 || true
      pkill -x AwakeMac 2>/dev/null && sleep 1 || true
      rm -rf "/Applications/Awake Mac.app"
      cp -R "$APP" /Applications/
      open "/Applications/Awake Mac.app"
      ;;
    --zip)
      mkdir -p dist
      ditto -c -k --keepParent "$APP" "dist/AwakeMac-$VERSION.zip"
      echo "==> dist/AwakeMac-$VERSION.zip"
      ;;
  esac
done
echo "Done."
