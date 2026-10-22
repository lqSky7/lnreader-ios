#!/bin/sh
# Chapter number parsing (against Yokai's reference cases) and chapter-list
# merging against a real in-memory store. Runs on macOS, no simulator needed.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-chapter-sync.XXXXXX)
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
  Services/Sources/SourceModels.swift \
  Services/Sources/ChapterRecognition.swift \
  Services/Sources/ChapterSourceSync.swift \
  tests/V2ChapterSyncChecks.swift \
  -o "$binary"
"$binary"
