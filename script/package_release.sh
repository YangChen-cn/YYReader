#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YYReader"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
OUTPUT_APP="$DIST_DIR/$APP_NAME.app"
OUTPUT_ZIP="$DIST_DIR/$APP_NAME-release.zip"
ENTITLEMENTS="$ROOT_DIR/YYReader/YYReader.entitlements"
SWIFT_PATH_MAP="-file-prefix-map $ROOT_DIR=YYReaderBuild"

source "$ROOT_DIR/script/portable_bundle.sh"

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
mkdir -p "$DIST_DIR"
rm -rf "$OUTPUT_APP" "$OUTPUT_ZIP"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT_APP"
sanitize_portable_bundle "$OUTPUT_APP"
sign_portable_bundle "$OUTPUT_APP" "$ENTITLEMENTS"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
verify_portable_bundle "$OUTPUT_APP" "$ROOT_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"
echo "Release: $OUTPUT_APP"
echo "Archive: $OUTPUT_ZIP"
