#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YYReader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
OUTPUT_APP="$DIST_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT_DIR/YYReader/YYReader.entitlements"
SWIFT_PATH_MAP="-file-prefix-map $ROOT_DIR=YYReaderBuild"
DMG_STAGING_DIR=""
DMG_MOUNT_DIR=""
DMG_ATTACHED=0

source "$ROOT_DIR/script/portable_bundle.sh"

cleanup() {
  if [[ "$DMG_ATTACHED" -eq 1 && -n "$DMG_MOUNT_DIR" ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet || true
  fi
  if [[ -n "$DMG_STAGING_DIR" && -d "$DMG_STAGING_DIR" ]]; then
    rm -rf "$DMG_STAGING_DIR"
  fi
  if [[ -n "$DMG_MOUNT_DIR" && -d "$DMG_MOUNT_DIR" ]]; then
    rmdir "$DMG_MOUNT_DIR" 2>/dev/null || true
  fi
}

trap cleanup EXIT

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
  -project YYReader.xcodeproj \
  -scheme YYReader \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  CLANG_COVERAGE_MAPPING=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEBUG_INFORMATION_FORMAT=dwarf \
  ENABLE_CODE_COVERAGE=NO \
  ENABLE_DEBUG_DYLIB=NO \
  ONLY_ACTIVE_ARCH=NO \
  "OTHER_SWIFT_FLAGS=$SWIFT_PATH_MAP" \
  clean build

VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$SOURCE_APP/Contents/Info.plist")"
OUTPUT_ZIP="$DIST_DIR/$APP_NAME-$VERSION-arm64.zip"
OUTPUT_DMG="$DIST_DIR/$APP_NAME-$VERSION-arm64.dmg"
LEGACY_ZIP="$DIST_DIR/$APP_NAME-release.zip"

mkdir -p "$DIST_DIR"
rm -rf "$OUTPUT_APP"
rm -f "$OUTPUT_ZIP" "$OUTPUT_DMG" "$LEGACY_ZIP"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT_APP"
sanitize_portable_bundle "$OUTPUT_APP"
sign_portable_bundle "$OUTPUT_APP" "$ENTITLEMENTS"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
verify_portable_bundle "$OUTPUT_APP" "$ROOT_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"

TEMP_PARENT="${TMPDIR:-/private/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
DMG_STAGING_DIR="$(mktemp -d "$TEMP_PARENT/$APP_NAME-dmg.XXXXXX")"
DMG_MOUNT_DIR="$(mktemp -d "$TEMP_PARENT/$APP_NAME-mount.XXXXXX")"
/usr/bin/ditto "$OUTPUT_APP" "$DMG_STAGING_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$DMG_STAGING_DIR/Applications"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -format UDZO \
  -ov \
  "$OUTPUT_DMG"
/usr/bin/hdiutil verify "$OUTPUT_DMG"
/usr/bin/hdiutil attach \
  -readonly \
  -nobrowse \
  -mountpoint "$DMG_MOUNT_DIR" \
  "$OUTPUT_DMG" >/dev/null
DMG_ATTACHED=1
/usr/bin/codesign --verify --deep --strict --verbose=2 "$DMG_MOUNT_DIR/$APP_NAME.app"
verify_portable_bundle "$DMG_MOUNT_DIR/$APP_NAME.app" "$ROOT_DIR"
/usr/bin/hdiutil detach "$DMG_MOUNT_DIR" -quiet
DMG_ATTACHED=0

echo "Release: $OUTPUT_APP"
echo "Archive: $OUTPUT_ZIP"
echo "Disk image: $OUTPUT_DMG"
