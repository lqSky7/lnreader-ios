#!/bin/sh
# Chapter image cache, page loader, prefetch ordering and manga progress.
# Headless, runs on macOS.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-page-pipeline.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Models/Schema/ContentKind.swift \
  Models/Schema/EntryStatus.swift \
  Services/Sources/SourceModels.swift \
  Services/Network/HTTPTypes.swift \
  Services/Network/Interceptors.swift \
  Services/Network/HTTPClient.swift \
  Services/Images/ChapterCache.swift \
  Services/Images/PageLoader.swift \
  Features/MangaReader/PagePrefetchPlan.swift \
  Features/MangaReader/MangaProgress.swift \
  tests/V2PagePipelineChecks.swift \
  -o "$binary"
"$binary"
