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

cd "$ROOT_DIR"
xcodegen generate
xcodebuild -project YYReader.xcodeproj -scheme YYReader -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO clean build
mkdir -p "$DIST_DIR"
rm -rf "$OUTPUT_APP" "$OUTPUT_ZIP"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT_APP"
/usr/bin/codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$OUTPUT_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"
echo "Release: $OUTPUT_APP"
echo "Archive: $OUTPUT_ZIP"
