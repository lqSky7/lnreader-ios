#!/bin/sh
# Library sort rules and the per-category store. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-library-sorts.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Enums/SortOrder.swift \
  Models/Enums/LibraryFilter.swift \
  Models/Enums/LibrarySort.swift \
  tests/LibrarySortChecks.swift \
  -o "$binary"
"$binary"
