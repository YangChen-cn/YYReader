#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YYReader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ENTITLEMENTS="$ROOT_DIR/YYReader/YYReader.entitlements"
SWIFT_PATH_MAP="-file-prefix-map $ROOT_DIR=YYReaderBuild"
# Normal releases are Apple-silicon only. Intel was built once for v1.0.0
# manually and is intentionally not part of the recurring release script.
ARCHITECTURES=(arm64)
TEMP_PARENT="${TMPDIR:-/private/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
WORK_DIR=""
MOUNT_DIR=""
DMG_ATTACHED=0

source "$ROOT_DIR/script/portable_bundle.sh"

cleanup() {
  if [[ "$DMG_ATTACHED" -eq 1 && -n "$MOUNT_DIR" ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
}

trap cleanup EXIT

cd "$ROOT_DIR"
xcodegen generate
mkdir -p "$DIST_DIR"

# The release contains DMG installers only. Remove archives from previous runs
# so a local dist directory cannot be mistaken for the published asset set.
find "$DIST_DIR" -maxdepth 1 -type f \( -name "$APP_NAME-*.zip" -o -name "$APP_NAME-*.dmg" \) -delete
rm -rf "$DIST_DIR/$APP_NAME.app" "$DIST_DIR/$APP_NAME-x86_64.app"

VERSION=""
for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
  DERIVED_DATA="$ROOT_DIR/DerivedData/$ARCHITECTURE"
  SOURCE_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

  xcodebuild \
    -project YYReader.xcodeproj \
    -scheme YYReader \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCHITECTURE" \
    VALID_ARCHS="$ARCHITECTURE" \
    CLANG_COVERAGE_MAPPING=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEBUG_INFORMATION_FORMAT=dwarf \
    ENABLE_CODE_COVERAGE=NO \
    ENABLE_DEBUG_DYLIB=NO \
    ONLY_ACTIVE_ARCH=NO \
    "OTHER_SWIFT_FLAGS=$SWIFT_PATH_MAP" \
    clean build

  if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$SOURCE_APP/Contents/Info.plist")"
  fi

  OUTPUT_DMG="$DIST_DIR/$APP_NAME-$VERSION-$ARCHITECTURE.dmg"
  WORK_DIR="$(mktemp -d "$TEMP_PARENT/$APP_NAME-release-$ARCHITECTURE.XXXXXX")"
  MOUNT_DIR="$(mktemp -d "$TEMP_PARENT/$APP_NAME-mount-$ARCHITECTURE.XXXXXX")"
  APP_COPY="$WORK_DIR/$APP_NAME.app"
  DMG_ROOT="$WORK_DIR/image"

  /usr/bin/ditto "$SOURCE_APP" "$APP_COPY"
  sanitize_portable_bundle "$APP_COPY"
  sign_portable_bundle "$APP_COPY" "$ENTITLEMENTS"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_COPY"
  verify_portable_bundle "$APP_COPY" "$ROOT_DIR"

  mkdir -p "$DMG_ROOT"
  /usr/bin/ditto "$APP_COPY" "$DMG_ROOT/$APP_NAME.app"
  /bin/ln -s /Applications "$DMG_ROOT/Applications"
  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_ROOT" \
    -format UDZO \
    -ov \
    "$OUTPUT_DMG"
  /usr/bin/hdiutil verify "$OUTPUT_DMG"
  /usr/bin/hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$MOUNT_DIR" \
    "$OUTPUT_DMG" >/dev/null
  DMG_ATTACHED=1
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/$APP_NAME.app"
  verify_portable_bundle "$MOUNT_DIR/$APP_NAME.app" "$ROOT_DIR"
  /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet
  DMG_ATTACHED=0

  rm -rf "$WORK_DIR"
  WORK_DIR=""
  rmdir "$MOUNT_DIR" 2>/dev/null || true
  MOUNT_DIR=""

  echo "Disk image ($ARCHITECTURE): $OUTPUT_DMG"

  # Release builds always `clean build`, so the DerivedData has no reuse
  # value. Remove the per-architecture products after the DMG is verified to
  # avoid leaving build intermediates behind.
  /bin/rm -rf "$DERIVED_DATA"
done
