#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${LINEDRAW_TEAM_ID:?Set your own Apple development team ID}"
: "${LINEDRAW_DEVICE_ID:?Set the test iPhone UDID}"
PROJECT="$ROOT/.runtime/DeviceRunnerSource/WebDriverAgent.xcodeproj"
[[ -d "$PROJECT" ]] || python3 "$ROOT/scripts/prepare-device-runner.py"
xcodebuild -project "$PROJECT" -scheme WebDriverAgentRunner -configuration Debug \
 -destination "id=$LINEDRAW_DEVICE_ID" -derivedDataPath "$ROOT/.runtime/DeviceRunnerBuild" \
 DEVELOPMENT_TEAM="$LINEDRAW_TEAM_ID" -allowProvisioningUpdates build-for-testing
SOURCE="$ROOT/.runtime/DeviceRunnerBuild/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"
OUT="$ROOT/.runtime/DeviceRunner-Preinstalled.app"
[[ ! -e "$OUT" ]] || { echo 'Move previous DeviceRunner-Preinstalled.app before rebuilding.' >&2; exit 1; }
ditto "$SOURCE" "$OUT"
# Appium's preinstalled Runner path uses device XCTest frameworks on recent iOS.
# Modify only our copied artifact; never touch the original Mac runner.
if [[ -d "$OUT/Frameworks" ]]; then find "$OUT/Frameworks" -maxdepth 1 -name 'XC*' -exec rm -rf {} +; fi
IDENTITY=$(codesign -dv "$SOURCE" 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)/\1/p' | head -1)
[[ -n "$IDENTITY" ]]
codesign -d --entitlements :- "$SOURCE" > "$ROOT/.runtime/runner-entitlements.plist" 2>/dev/null
codesign --force --sign "$IDENTITY" --preserve-metadata=identifier --entitlements "$ROOT/.runtime/runner-entitlements.plist" "$OUT"
codesign --verify --deep --strict "$OUT"
echo "$OUT"
