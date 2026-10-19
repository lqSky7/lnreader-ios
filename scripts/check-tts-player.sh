#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${1:?Usage: check-tts-player.sh complete-package-folder [stream-parts-folder]}"
binary=$(mktemp /tmp/lnreader-player-checks.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library Models/TTSAudio.swift Services/ReaderTTSManager.swift tests/TTSPlayerChecks.swift -o "$binary"
"$binary" "$@"
