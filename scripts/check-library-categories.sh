#!/bin/sh
# Per-category display mode, update exclusion flag and update scope. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-library-categories.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Enums/DisplayMode.swift \
  Models/Enums/LibraryFilter.swift \
  Models/Enums/CategorySettings.swift \
  tests/CategorySettingsChecks.swift \
  -o "$binary"
"$binary"
