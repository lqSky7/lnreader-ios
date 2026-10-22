#!/bin/sh
# Decodes and restores .tachibk backups against an in-memory SwiftData store.
# Optional: TACHIBK_SAMPLE=/path/to/export.tachibk also runs a real file.
# Runs on macOS, no simulator needed.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-mihon-backup.XXXXXX)
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
  Services/Extensions/ExtensionStore.swift \
  Services/Extensions/BundledExtensions.swift \
  Services/Backup/ProtobufReader.swift \
  Services/Backup/MihonBackup.swift \
  Utilities/Gzip.swift \
  tests/MihonBackupChecks.swift \
  -o "$binary"
"$binary"
