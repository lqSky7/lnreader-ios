#!/bin/sh
# Records an Instruments trace of LNReader on a connected iPhone.
#
# The headless benchmark (`profile-hotpaths.sh`) covers data work; this covers
# everything it cannot see — SwiftUI body evaluation, layout, WebKit, image
# decode. Run it, reproduce the bad screen for the duration, then open the
# .trace in Instruments.
#
#   ./scripts/profile-device.sh                 # 30 s, Time Profiler
#   ./scripts/profile-device.sh 60              # 60 s
#   ./scripts/profile-device.sh 30 com.lnreader.app
#
# Requires the app already installed and running on the device. `xctrace
# --attach` needs a debuggable build, so install a Debug build for this.
set -eu
cd "$(dirname "$0")/.."

DURATION=${1:-30}
BUNDLE_ID=${2:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Info.plist 2>/dev/null || echo "com.lnreader.app")}
OUT="perf-$(date +%Y%m%d-%H%M%S).trace"

if ! xcrun xctrace list devices 2>/dev/null | grep -q "iPhone"; then
  echo "profile-device: no iPhone visible to xctrace." >&2
  echo "" >&2
  echo "Connect and trust the device, then check that it appears here:" >&2
  echo "  xcrun xctrace list devices" >&2
  echo "" >&2
  echo "Without a device, run the headless benchmark instead:" >&2
  echo "  ./scripts/profile-hotpaths.sh" >&2
  exit 1
fi

echo "profile-device: recording ${DURATION}s of $BUNDLE_ID -> $OUT"
echo "profile-device: reproduce the slow screen now."

# Time Profiler for CPU, Points of Interest for the signposts the app emits,
# Allocations for the image caches.
xcrun xctrace record \
  --template 'Time Profiler' \
  --device "$(xcrun xctrace list devices | awk '/iPhone/ {print $0; exit}' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')" \
  --attach "$BUNDLE_ID" \
  --time-limit "${DURATION}s" \
  --output "$OUT"

echo ""
echo "profile-device: wrote $OUT"
echo "  open $OUT                       # Instruments"
echo ""
echo "What to look at, in order:"
echo "  1. Heaviest Stack Trace — is the main thread inside a SwiftUI body, a"
echo "     SwiftData fetch, or WebKit?"
echo "  2. Call Tree -> check 'Hide System Libraries' and 'Invert Call Tree' to"
echo "     see which of *our* symbols dominate."
echo "  3. Time Profiler -> 'Separate by Thread' — main thread work that is not"
echo "     layout is the thing to move off it."
