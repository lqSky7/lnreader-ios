#!/bin/sh
# Scanlator dedup and visibility rules. Headless.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-scanlators.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Features/Novel/ScanlatorRules.swift \
  tests/V2ScanlatorChecks.swift \
  -o "$binary"
"$binary"
