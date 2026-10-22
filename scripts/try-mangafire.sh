#!/bin/sh
# Runs the MangaFire bundle through the real extension host against the live
# API. Needs network access; not part of the offline check suite.
set -eu
cd "$(dirname "$0")/.."

SWIFTSOUP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/LNReader-*/SourcePackages/checkouts/SwiftSoup/Sources 2>/dev/null | head -1)
MODDIR=/tmp/lnr-mac
BUNDLE=${BUNDLE:-../lnreader-extensions/extensions/mangafire/mangafire.js}

if [ ! -f "$MODDIR/libSwiftSoup.a" ]; then
  mkdir -p "$MODDIR"
  xcrun swiftc -emit-library -static -disable-sandbox -module-name SwiftSoup \
    -o "$MODDIR/libSwiftSoup.a" -emit-module-path "$MODDIR/SwiftSoup.swiftmodule" \
    "$SWIFTSOUP"/*.swift
fi

binary=$(mktemp /tmp/lnreader-mangafire.XXXXXX)
trap 'rm -f "$binary"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Schema/ContentKind.swift \
  Models/Schema/EntryStatus.swift \
  Services/Sources/SourceKey.swift \
  Services/Sources/SourceModels.swift \
  Services/Sources/SourceFilters.swift \
  Services/Sources/CatalogSource.swift \
  Services/Network/HTTPTypes.swift \
  Services/Network/Interceptors.swift \
  Services/Network/HTTPClient.swift \
  Services/Extensions/ExtensionContract.swift \
  Services/Extensions/JSExtensionHost.swift \
  Services/Extensions/JSBundleMangaSource.swift \
  Utilities/DateParsing.swift \
  tests/MangaFireLiveChecks.swift \
  -I "$MODDIR" -L "$MODDIR" -lSwiftSoup \
  -o "$binary"

MANGA_BUNDLE="$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")" "$binary"
