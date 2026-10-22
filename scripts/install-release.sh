#!/bin/sh
# install-release.sh — build a Release LNReader and install it on the first
# connected physical iPhone/iPad.
#
#   ./scripts/install-release.sh            # build, install, launch
#   ./scripts/install-release.sh --no-launch
#
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
DEVICES_JSON=$(mktemp)
trap 'rm -f "$DEVICES_JSON"' EXIT

xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
# First physical device that is currently connected: "<identifier>\t<name>".
DEVICE=$(python3 -I - "$DEVICES_JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except (OSError, ValueError, KeyError):
    sys.exit(0)
for d in devices:
    hardware = d.get("hardwareProperties", {})
    if hardware.get("reality") == "physical" and d.get("connectionProperties", {}).get("tunnelState") == "connected":
        print(f'{d["identifier"]}\t{d.get("deviceProperties", {}).get("name", "device")}')
        break
PY
)

if [ -z "$DEVICE" ]; then
  echo "install-release: no connected physical device." >&2
  echo "Connect and unlock it, tap Trust, then check:  xcrun devicectl list devices" >&2
  exit 1
fi
DEVICE_ID=${DEVICE%%	*}
DEVICE_NAME=${DEVICE#*	}

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
