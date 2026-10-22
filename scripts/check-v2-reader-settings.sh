#!/bin/sh
# Per-series manga reader settings: resolution, persistence, reset. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-reader-settings.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Features/MangaReader/MangaReadingMode.swift \
  Features/MangaReader/MangaReaderControls.swift \
  Features/MangaReader/MangaReaderSettings.swift \
  tests/V2ReaderSettingsChecks.swift \
  -o "$binary"
"$binary"
