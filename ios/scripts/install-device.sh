#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/install-device.sh DEVICE_ID [TEAM_ID]"
    echo "Find the device ID with: xcrun devicectl list devices"
    echo "Choose your Personal Team in Xcode → Treehouse target → Signing & Capabilities first."
    exit 1
fi

device_id="$1"
signing_args=("CODE_SIGN_STYLE=Automatic")
if [[ $# -ge 2 ]]; then signing_args+=("DEVELOPMENT_TEAM=$2"); fi
xcodebuild -project Treehouse.xcodeproj -scheme Treehouse -configuration Debug \
    -destination "platform=iOS,id=$device_id" -derivedDataPath build-device \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration "${signing_args[@]}" build
xcrun devicectl device install app --device "$device_id" build-device/Build/Products/Debug-iphoneos/Treehouse.app
xcrun devicectl device process launch --device "$device_id" house.tree310.treehouse
