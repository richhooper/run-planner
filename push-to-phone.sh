#!/bin/bash
# Builds Run Planner, installs it on the iPhone and launches it.
# Usage: ./push-to-phone.sh [device-udid]
# Free Apple accounts expire the install after 7 days; run this to renew it.
set -euo pipefail

DEVICE="${1:-00008140-000224422247001C}"   # Rich Phone
BUNDLE_ID="com.richardhooper.runplanner"

cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/opt/homebrew/bin:$PATH"

DERIVED_DATA="build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/RunPlanner.app"
LOG="build/push-to-phone.log"
mkdir -p build

if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE"; then
    echo "Can't find the iPhone ($DEVICE). Plug it in, unlock it and try again." >&2
    exit 1
fi

echo "==> Generating Xcode project"
xcodegen --quiet

echo "==> Building (log: $LOG)"
if ! xcodebuild -project RunPlanner.xcodeproj -scheme RunPlanner \
        -destination "id=$DEVICE" -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates build >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u >&2 || tail -20 "$LOG" >&2
    echo "Build failed. Full log: $LOG" >&2
    exit 1
fi

echo "==> Installing on iPhone"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

echo "==> Launching"
if ! output=$(xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1); then
    if grep -q "explicitly trusted" <<<"$output"; then
        echo "Installed, but the iPhone needs you to approve it first:" >&2
        echo "Settings > General > VPN & Device Management > your Apple ID > Trust (or Verify App)." >&2
        echo "Then open Run Planner on the phone, or run this script again." >&2
    elif grep -qi "locked" <<<"$output"; then
        echo "Installed, but the iPhone is locked. Unlock it and open Run Planner." >&2
    else
        echo "$output" >&2
    fi
    exit 1
fi

expiry=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)
echo "Done. Run Planner is open on your iPhone. This install expires ${expiry%%T*}."
