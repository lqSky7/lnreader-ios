#!/bin/bash
# Typechecks the whole app without Xcode or SwiftPM.
#
# Why this exists: `xcodebuild` resolves packages and runs the macro plugin
# server inside nested sandboxes, which fails in restricted environments. This
# drives swiftc directly, so the two SPM dependencies have to be prebuilt as
# modules. They are built on demand into $MODDIR (default /tmp/lnr-mod).
#
# If Xcode can build the project normally, prefer that.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
TARGET=arm64-apple-ios26.0
MODDIR=${MODDIR:-/tmp/lnr-mod}
mkdir -p "$MODDIR"

# SwiftPM synthesises `Bundle.module` for targets that declare resources.
# `swiftc -emit-module` does not, so Glur fails to compile without a stand-in.
# Typechecking only needs the declaration; the real build uses SPM.
BUNDLE_STUB="$MODDIR/BundleStub.swift"
if [ ! -f "$BUNDLE_STUB" ]; then
  cat > "$BUNDLE_STUB" <<'STUB'
import Foundation

extension Bundle {
    static let module = Bundle.main
}
STUB
fi

# SourcePackages/checkouts, wherever Xcode put them.
CHECKOUTS=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/LNReader-*/SourcePackages/checkouts 2>/dev/null | head -1)
if [ -z "$CHECKOUTS" ]; then
  echo "typecheck: no SPM checkouts found — open the project in Xcode once." >&2
  exit 1
fi

# Build a module if it is not cached yet.
#   build_module <module> <sources dir> [dependency modules...]
build_module() {
  module=$1
  sources=$2
  shift 2

  if [ -f "$MODDIR/$module.swiftmodule" ]; then
    return 0
  fi

  echo "typecheck: building $module module (once)"

  # -I is always passed: GlurBackdrop depends on Glur, and a redundant include
  # path costs nothing. (macOS ships bash 3.2, where an empty array under
  # `set -u` is an unbound variable.)
  if ! xcrun swiftc -emit-module -disable-sandbox \
    -module-name "$module" -target "$TARGET" -sdk "$SDK" -swift-version 5 \
    -I "$MODDIR" \
    -emit-module-path "$MODDIR/$module.swiftmodule" \
    "$sources"/*.swift "$BUNDLE_STUB"; then
    echo "typecheck: could not build $module" >&2
    exit 1
  fi
}

build_module SwiftSoup "$CHECKOUTS/SwiftSoup/Sources"
build_module Glur "$CHECKOUTS/Glur/Sources/Glur"
build_module GlurBackdrop "$CHECKOUTS/Glur/Sources/GlurBackdrop" Glur

FILES=$(find LNReaderApp.swift ContentView.swift Components Design Extensions Features Models Services Utilities -name "*.swift")
xcrun swiftc -typecheck -disable-sandbox \
  -target "$TARGET" -sdk "$SDK" -swift-version 5 -enable-bare-slash-regex -D DEBUG \
  -I "$MODDIR" -module-name LNReader \
  $FILES
