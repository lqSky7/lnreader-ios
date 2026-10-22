#!/bin/sh
# Runs a JS extension bundle through the real host: JSC -> HTTP bridge ->
# SwiftSoup -> SourceEntry/Chapter/Page. Fixtures are served from a local
# directory so the check never depends on a live site.
set -eu
cd "$(dirname "$0")/.."

SWIFTSOUP=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/LNReader-*/SourcePackages/checkouts/SwiftSoup/Sources 2>/dev/null | head -1)
if [ -z "$SWIFTSOUP" ]; then
  echo "SwiftSoup checkout not found; open the project in Xcode once so SPM resolves." >&2
  exit 1
fi

MODDIR=/tmp/lnr-mac
if [ ! -f "$MODDIR/libSwiftSoup.a" ]; then
  mkdir -p "$MODDIR"
  echo "Building SwiftSoup for macOS (once)…"
  xcrun swiftc -emit-library -static -disable-sandbox -module-name SwiftSoup \
    -o "$MODDIR/libSwiftSoup.a" -emit-module-path "$MODDIR/SwiftSoup.swiftmodule" \
    "$SWIFTSOUP"/*.swift
fi

PORT=${PORT:-8123}
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory tests/fixtures/extensions >/tmp/lnr-extension-server.log 2>&1 &
SERVER_PID=$!

binary=$(mktemp /tmp/lnreader-extensions.XXXXXX)
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  rm -f "$binary"
}
trap cleanup EXIT INT TERM

# Wait for the server to accept connections.
i=0
while [ $i -lt 50 ]; do
  if curl -sf "http://127.0.0.1:$PORT/list.html" >/dev/null 2>&1; then break; fi
  i=$((i + 1))
  sleep 0.1
done

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
  Services/Extensions/WebViewCapture.swift \
  Services/Extensions/JSExtensionHost.swift \
  Services/Extensions/JSBundleMangaSource.swift \
  Utilities/DateParsing.swift \
  tests/V2ExtensionChecks.swift \
  -I "$MODDIR" -L "$MODDIR" -lSwiftSoup \
  -o "$binary"

FIXTURE_BASE_URL="http://127.0.0.1:$PORT" "$binary"
