#!/bin/bash
# Typechecks the whole app without Xcode or SwiftPM.
#
# Why this exists: `xcodebuild` resolves packages and runs the macro plugin
# server inside nested sandboxes, which fails in restricted environments. This
# drives swiftc directly, which needs prebuilt modules for the two SPM
# dependencies:
#
#   MODDIR (default /tmp/lnr-mod) must contain SwiftSoup.swiftmodule and
#   Glur.swiftmodule for arm64-apple-ios26.0. Build them once with:
#
#     xcrun swiftc -emit-module -disable-sandbox -module-name SwiftSoup \
#       -target arm64-apple-ios26.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
#       -swift-version 5 -emit-module-path /tmp/lnr-mod/SwiftSoup.swiftmodule \
#       <SourcePackages/checkouts/SwiftSoup/Sources/*.swift>
#
# If Xcode can build the project normally, prefer that.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MODDIR=${MODDIR:-/tmp/lnr-mod}

FILES=$(find LNReaderApp.swift ContentView.swift Components Design Extensions Features Models Services Utilities -name "*.swift")
xcrun swiftc -typecheck -disable-sandbox \
  -target arm64-apple-ios26.0 -sdk "$SDK" -swift-version 5 -enable-bare-slash-regex -D DEBUG \
  -I "$MODDIR" -module-name LNReader \
  $FILES
