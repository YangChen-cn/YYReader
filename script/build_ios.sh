#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-build}"
cd "$ROOT_DIR"
case "$MODE" in
  build|ipa) exec "$ROOT_DIR/script/package_ios.sh" unsigned ;;
  signed) exec "$ROOT_DIR/script/package_ios.sh" signed ;;
  release) exec "$ROOT_DIR/script/package_ios.sh" unsigned Release ;;
  simulator|test)
    xcodegen generate
    SIMULATOR_ID="${YYREADER_SIMULATOR_ID:-}"
    if [[ -z "$SIMULATOR_ID" ]]; then
      SIMULATOR_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
devices = [d for runtime, values in json.load(sys.stdin)["devices"].items()
           if "iOS" in runtime for d in values if d.get("isAvailable")]
devices.sort(key=lambda d: (d["state"] != "Booted", "iPhone" not in d["name"]))
print(devices[0]["udid"] if devices else "")')"
    fi
    if [[ -z "$SIMULATOR_ID" ]]; then
      echo "No iOS simulator. Install an iOS runtime in Xcode Settings > Components." >&2
      exit 1
    fi
    if [[ "$MODE" == test ]]; then
      xcodebuild test -project YYReader.xcodeproj -scheme YYReaderIOS \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath "$ROOT_DIR/DerivedData/iOSSimulator" CODE_SIGNING_ALLOWED=NO
    else
      xcodebuild build -project YYReader.xcodeproj -scheme YYReaderIOS \
        -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
        -derivedDataPath "$ROOT_DIR/DerivedData/iOSSimulator" CODE_SIGNING_ALLOWED=NO
      if ! xcrun simctl list devices booted | /usr/bin/grep -q "$SIMULATOR_ID"; then
        xcrun simctl boot "$SIMULATOR_ID"
      fi
      xcrun simctl bootstatus "$SIMULATOR_ID" -b
      xcrun simctl install "$SIMULATOR_ID" "$ROOT_DIR/DerivedData/iOSSimulator/Build/Products/Debug-iphonesimulator/YYReader.app"
      xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.yyreader.ios
      SIMULATOR_APP="$(xcode-select -p)/Applications/Simulator.app"
      if [[ -d "$SIMULATOR_APP" ]]; then
        open -a "$SIMULATOR_APP"
      else
        open -a "Device Hub"
      fi
    fi
    ;;
  *) echo "usage: $0 [build|ipa|signed|release|simulator|test]" >&2; exit 2 ;;
esac
