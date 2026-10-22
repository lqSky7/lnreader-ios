#!/bin/sh
# Builds the v2 SwiftData schema in an in-memory container and drives it like
# the app will: library round-trip, chapter state, categories, history cascade,
# download queue, unique constraints. Runs on macOS, no simulator needed.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-v2-schema.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Schema/ContentKind.swift \
  Models/Schema/EntryStatus.swift \
  Models/Schema/UpdateStrategy.swift \
  Models/Schema/DownloadState.swift \
  Models/Schema/SchemaV1.swift \
  Models/Schema/SchemaMigrationPlan.swift \
  Models/UserProfile.swift \
  Services/Sources/SourceKey.swift \
  tests/V2SchemaChecks.swift \
  -o "$binary"
"$binary"
