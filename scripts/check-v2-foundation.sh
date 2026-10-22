#!/bin/sh
# Behaviour checks for the v2 foundation layer (schema enums, source values,
# filters, dates, HTTP value types). Compiles only the platform-independent
# files, so it runs on macOS without a simulator.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-v2-foundation.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library \
  Models/Schema/ContentKind.swift \
  Models/Schema/EntryStatus.swift \
  Services/Sources/SourceModels.swift \
  Services/Sources/SourceFilters.swift \
  Services/Network/HTTPTypes.swift \
  Services/Network/Interceptors.swift \
  Utilities/DateParsing.swift \
  tests/V2FoundationChecks.swift \
  -o "$binary"
"$binary"
