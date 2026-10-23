#!/bin/sh
# Library badge rules and language labels. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-library-badges.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Enums/LibraryBadges.swift \
  tests/LibraryBadgeChecks.swift \
  -o "$binary"
"$binary"
