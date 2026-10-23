#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-offline-checks.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Schema/ContentKind.swift Models/Schema/EntryStatus.swift \
  Models/Schema/UpdateStrategy.swift Models/Schema/DownloadState.swift \
  Models/Schema/SchemaV1.swift Models/UserProfile.swift \
  Services/Sources/SourceKey.swift Services/Sources/SourceModels.swift \
  Services/LibraryBackup.swift Services/OfflineChapters.swift tests/OfflineLibraryChecks.swift -o "$binary"
"$binary"
