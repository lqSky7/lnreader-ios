#!/bin/sh
# Chapter image cache and page prefetch ordering. Headless, runs on macOS.
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-page-pipeline.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -disable-sandbox \
  Services/Images/ChapterCache.swift \
  Features/MangaReader/PagePrefetchPlan.swift \
  tests/V2PagePipelineChecks.swift \
  -o "$binary"
"$binary"
