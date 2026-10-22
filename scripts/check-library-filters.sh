#!/bin/sh
# Library filter rules and the per-category store. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-library-filters.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Enums/LibraryFilter.swift \
  tests/LibraryFilterChecks.swift \
  -o "$binary"
"$binary"
