#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/lnreader-native-comments.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
mkdir -p "$check_dir/Sources/Checks"
cp Services/NovelFireCommentsService.swift Services/CommentSite.swift tests/NativeCommentsChecks.swift "$check_dir/Sources/Checks/"
python3 - "$check_dir/Package.swift" <<'PY'
import json, os, sys
checkout = os.environ.get('SWIFTSOUP_CHECKOUT')
dependency = '.package(path: ' + json.dumps(checkout) + ')' if checkout else '.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3")'
open(sys.argv[1], 'w').write('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NativeCommentChecks", platforms: [.macOS(.v14)], dependencies: [''' + dependency + '''], targets: [.executableTarget(name: "Checks", dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")])])
''')
PY
swift run --package-path "$check_dir" --scratch-path /tmp/lnreader-native-comment-checks-build Checks
