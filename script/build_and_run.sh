#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="YYReader"
BUNDLE_ID="com.yyreader.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ENTITLEMENTS="$ROOT_DIR/YYReader/YYReader.entitlements"
RUN_STAGING_DIR="/private/tmp/${APP_NAME}-run-${UID}"
RUN_BUNDLE="$RUN_STAGING_DIR/$APP_NAME.app"
SWIFT_PATH_MAP="-file-prefix-map $ROOT_DIR=YYReaderBuild"

source "$ROOT_DIR/script/portable_bundle.sh"

cd "$ROOT_DIR"
if [[ "$MODE" != "build-only" && "$MODE" != "--build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
xcodegen generate
xcodebuild \
  -project YYReader.xcodeproj \
  -scheme YYReader \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO \
  ENABLE_DEBUG_DYLIB=NO \
  "OTHER_SWIFT_FLAGS=$SWIFT_PATH_MAP" \
  build

mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
/usr/bin/ditto "$SOURCE_APP" "$APP_BUNDLE"
sanitize_portable_bundle "$APP_BUNDLE"
sign_portable_bundle "$APP_BUNDLE" "$ENTITLEMENTS"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
verify_portable_bundle "$APP_BUNDLE" "$ROOT_DIR"

open_app() {
  rm -rf "$RUN_BUNDLE"
  mkdir -p "$RUN_STAGING_DIR"
  /usr/bin/ditto "$APP_BUNDLE" "$RUN_BUNDLE"
  /usr/bin/open -n "$RUN_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not remain running after launch" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
