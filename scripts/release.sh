#!/usr/bin/env bash
# Signed (Developer ID) + notarized + stapled release, using the Apple account
# that is signed in to Xcode (Xcode › Settings › Accounts). No passwords here.
#
#   ./scripts/release.sh            -> dist/AwakeMac-<version>.zip
#   ./scripts/release.sh --publish  -> also creates the GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM_ID=${TEAM_ID:-AQ2Y664A4Z} # public identifier, embedded in every signed build
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Config/Info.plist)
ARCHIVE=build/AwakeMac.xcarchive
EXPORT=build/export
APP="$EXPORT/Awake Mac.app"
ZIP="dist/AwakeMac-$VERSION.zip"
rm -rf "$ARCHIVE" "$EXPORT"; mkdir -p dist

echo "==> Archiving $VERSION (universal)"
xcodebuild -project AwakeMac.xcodeproj -scheme AwakeMac -configuration Release \
  -derivedDataPath build/xc -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" ONLY_ACTIVE_ARCH=NO archive | grep -E "error|warning:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || { echo "archive failed"; exit 1; }

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
PLIST

echo "==> Signing with Developer ID and uploading to Apple's notary service"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT" -allowProvisioningUpdates | grep -E "error|EXPORT" || true

echo "==> Waiting for notarization (usually 1–5 min)"
for i in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT" >/dev/null 2>&1; then break; fi
  sleep 20
done
[ -d "$APP" ] || { echo "notarized app not available yet — run: xcodebuild -exportNotarizedApp -archivePath $ARCHIVE -exportPath $EXPORT"; exit 1; }

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier"
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "==> $ZIP"
echo "    sha256 $SHA"

if [ "${1:-}" = "--publish" ]; then
  gh release create "v$VERSION" "$ZIP" --title "Awake Mac $VERSION" \
    --notes-file <(sed -n "/^## $VERSION/,/^## /p" CHANGELOG.md | sed '$d'; echo; echo "SHA-256: \`$SHA\`")
fi
