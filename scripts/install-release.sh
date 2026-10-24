#!/bin/sh
# install-release.sh — build a Release LNReader and install it on the first
# connected physical iPhone/iPad.
#
#   ./scripts/install-release.sh            # build, install, launch
#   ./scripts/install-release.sh --no-launch
#
# Works over USB or Wi-Fi (the phone must be on the same network).
# Signs with the project's automatic signing settings, so the
# device must be unlocked, trusted, and have Developer Mode on. Run this from a
# normal terminal; inside an agent sandbox xcodebuild cannot resolve packages.
set -eu
cd "$(dirname "$0")/.."

LAUNCH=1
for argument in "$@"; do
  case "$argument" in
    --no-launch) LAUNCH=0 ;;
    *) echo "install-release: unknown option '$argument'" >&2; exit 2 ;;
  esac
done

DERIVED=.build/device
DEVICE=$(./scripts/lib/pick-device.sh)

if [ -z "$DEVICE" ]; then
  echo "install-release: no paired physical device." >&2
  echo "Pair it (USB once, then Connect via network in Xcode > Devices), then check:  xcrun devicectl list devices" >&2
  exit 1
fi
DEVICE_ID=$(printf '%s' "$DEVICE" | cut -f1)
DEVICE_NAME=$(printf '%s' "$DEVICE" | cut -f3)

echo "install-release: building Release for $DEVICE_NAME"
xcodebuild \
  -project LNReader.xcodeproj \
  -scheme LNReader \
  -configuration Release \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/LNReader.app"
[ -d "$APP" ] || { echo "install-release: build did not produce $APP" >&2; exit 1; }
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

echo "install-release: installing $BUNDLE_ID on $DEVICE_NAME"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

if [ "$LAUNCH" -eq 1 ]; then
  xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"
fi
echo "install-release: done"
