#!/bin/sh
# build-ipa.sh — build LNReader and package an unsigned .ipa.
#
#   ./scripts/build-ipa.sh                 # Debug
#   ./scripts/build-ipa.sh release         # Release
#   ./scripts/build-ipa.sh --checks        # run scripts/typecheck.sh first
#
# Output: LNReader-<version>-unsigned.ipa in the repository root
#
# The IPA is NOT signed. Sideloadly, AltStore or Xcode re-sign it with your own
# certificate; an unsigned bundle will not install on its own.
#
# Run this from a normal terminal. Inside an agent sandbox, xcodebuild cannot
# resolve packages and dies with:
#   sandbox-exec: sandbox_apply: Operation not permitted
set -eu

cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

CONFIG=Debug
RUN_CHECKS=0
for argument in "$@"; do
  case "$argument" in
    debug|Debug) CONFIG=Debug ;;
    release|Release) CONFIG=Release ;;
    --checks) RUN_CHECKS=1 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "build-ipa: unknown argument '$argument' (try --help)" >&2
      exit 2
      ;;
  esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
OUTPUT="$PROJECT_ROOT/LNReader-${VERSION}-unsigned.ipa"

echo "==> LNReader ${VERSION} (${BUILD}), ${CONFIG}"

if [ "$RUN_CHECKS" -eq 1 ]; then
  echo "==> Typecheck"
  ./scripts/typecheck.sh
fi

# Where Xcode will put the product, without guessing at DerivedData paths.
echo "==> Locating build products"
PRODUCTS_DIR=$(
  xcodebuild -project LNReader.xcodeproj -scheme LNReader \
    -configuration "$CONFIG" -sdk iphoneos \
    -disableAutomaticPackageResolution -showBuildSettings 2>/dev/null \
  | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1
)
if [ -z "$PRODUCTS_DIR" ]; then
  echo "build-ipa: could not read BUILT_PRODUCTS_DIR" >&2
  exit 1
fi

echo "==> Building"
# ENABLE_DEBUG_DYLIB=NO: the default Debug build is a stub launcher plus a
# dylib, which breaks once a sideloading tool re-signs it.
xcodebuild -project LNReader.xcodeproj -scheme LNReader \
  -configuration "$CONFIG" -sdk iphoneos -destination 'generic/platform=iOS' \
  -disableAutomaticPackageResolution \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$PRODUCTS_DIR/LNReader.app"
if [ ! -d "$APP" ]; then
  echo "build-ipa: no app at $APP" >&2
  exit 1
fi

echo "==> Packaging"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/lnreader-ipa.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
mkdir -p "$STAGE/Payload"
# -R keeps symlinks and resource forks intact; a plain cp can corrupt frameworks.
cp -R "$APP" "$STAGE/Payload/LNReader.app"

rm -f "$OUTPUT"
# -y stores symlinks as symlinks, which iOS expects inside an app bundle.
(cd "$STAGE" && zip -qry "$OUTPUT" Payload)

# Sanity checks: an IPA that is missing its binary or assets is not shippable.
for required in "Payload/LNReader.app/LNReader" "Payload/LNReader.app/Info.plist" \
                "Payload/LNReader.app/Assets.car"; do
  if ! unzip -l "$OUTPUT" | awk -v path="$required" 'index($0, path) { found = 1 } END { exit !found }'; then
    echo "build-ipa: $OUTPUT is missing $required" >&2
    exit 1
  fi
done

SIZE=$(du -h "$OUTPUT" | cut -f1 | tr -d ' ')
echo
echo "==> $OUTPUT ($SIZE)"
echo "    Bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "    Unsigned — re-sign with Sideloadly, AltStore or Xcode before installing."
