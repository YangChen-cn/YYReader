#!/usr/bin/env bash
set -euo pipefail

# No Mac release build or DMG is produced by this script.
MODE="${1:-unsigned}"
IOS_CONFIGURATION="${2:-Debug}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/DerivedData/iOS"
DIST_DIR="$ROOT_DIR/dist/iOS"
case "$MODE" in
  unsigned|signed) ;;
  *) echo "usage: $0 [unsigned|signed] [Debug|Release]" >&2; exit 2 ;;
esac
case "$IOS_CONFIGURATION" in
  Debug|Release) ;;
  *) echo "Configuration must be Debug or Release." >&2; exit 2 ;;
esac
if [[ "$MODE" == signed && -z "${YYREADER_IOS_TEAM_ID:-}" ]]; then
  echo "Set YYREADER_IOS_TEAM_ID to your Apple Developer team ID for a signed IPA." >&2
  exit 2
fi
cd "$ROOT_DIR"
xcodegen generate
mkdir -p "$DIST_DIR"
if [[ "$MODE" == unsigned ]]; then
  xcodebuild build -project YYReader.xcodeproj -scheme YYReaderIOS \
    -configuration "$IOS_CONFIGURATION" -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO
  SOURCE_APP="$BUILD_DIR/Build/Products/$IOS_CONFIGURATION-iphoneos/YYReader.app"
  STAGING_DIR="$(mktemp -d "$DIST_DIR/.ipa.XXXXXX")"
  trap 'rm -rf "$STAGING_DIR"' EXIT
  mkdir -p "$STAGING_DIR/Payload"
  ditto "$SOURCE_APP" "$STAGING_DIR/Payload/YYReader.app"
  APP="$STAGING_DIR/Payload/YYReader.app"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
  [[ "$(lipo -archs "$APP/YYReader")" == arm64 ]]
  [[ -f "$APP/Assets.car" ]]
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName' "$APP/Info.plist" | /usr/bin/grep -qx AppIcon
  IPA="$DIST_DIR/YYReader-iOS-$VERSION-resign.ipa"
  rm -f "$IPA"
  (cd "$STAGING_DIR" && /usr/bin/zip -qry "$IPA" Payload)
  /usr/bin/unzip -tq "$IPA"
  (cd "$DIST_DIR" && /usr/bin/shasum -a 256 "$(basename "$IPA")" > "$(basename "$IPA").sha256")
  echo "Configuration: $IOS_CONFIGURATION"
  echo "IPA for re-signing: $IPA"
  echo "This unsigned IPA needs Apple signing and a provisioning profile before installation."
else
  ARCHIVE="$BUILD_DIR/YYReaderIOS.xcarchive"
  xcodebuild archive -project YYReader.xcodeproj -scheme YYReaderIOS \
    -configuration "$IOS_CONFIGURATION" -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates "DEVELOPMENT_TEAM=$YYREADER_IOS_TEAM_ID" ENABLE_DEBUG_DYLIB=NO
  OPTIONS="$BUILD_DIR/ExportOptions.plist"
  /usr/bin/python3 - "$OPTIONS" "$YYREADER_IOS_TEAM_ID" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'method': 'debugging', 'teamID': sys.argv[2],
                  'signingStyle': 'automatic', 'stripSwiftSymbols': False}, output)
PY
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
    -exportPath "$DIST_DIR/signed" -allowProvisioningUpdates
  /usr/bin/codesign --verify --deep --strict "$ARCHIVE/Products/Applications/YYReader.app"
  /usr/bin/unzip -tq "$DIST_DIR/signed/YYReader.ipa"
  echo "Signed IPA: $DIST_DIR/signed/YYReader.ipa"
fi
