#!/bin/sh
# pick-device.sh — print the first paired physical iPhone/iPad as
# "<coredevice id>\t<udid>\t<name>", or nothing if there is none.
#
# `devicectl` takes the CoreDevice id, `xctrace` takes the UDID, so both are
# printed. A paired device over Wi-Fi reports tunnelState "disconnected" until
# a command opens the tunnel, so any paired device is accepted and one that is
# already connected is preferred.
set -eu

JSON=$(mktemp)
trap 'rm -f "$JSON"' EXIT
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true

python3 -I - "$JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except (OSError, ValueError, KeyError):
    sys.exit(0)
best = None
for d in devices:
    hardware = d.get("hardwareProperties", {})
    connection = d.get("connectionProperties", {})
    if hardware.get("reality") != "physical" or connection.get("pairingState") != "paired":
        continue
    connected = connection.get("tunnelState") == "connected"
    if best is None or (connected and not best[0]):
        name = d.get("deviceProperties", {}).get("name", "device")
        best = (connected, f'{d["identifier"]}\t{hardware.get("udid", "")}\t{name}')
if best:
    print(best[1])
PY
