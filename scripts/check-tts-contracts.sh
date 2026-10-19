#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
binary=$(mktemp /tmp/lnreader-tts-contracts.XXXXXX)
trap 'rm -f "$binary"' EXIT
xcrun swiftc -parse-as-library Models/TTSAudio.swift Features/Reader/ReaderTTSJavaScript.swift Services/TTSChapterSource.swift tests/TTSContractChecks.swift -o "$binary"
"$binary"
