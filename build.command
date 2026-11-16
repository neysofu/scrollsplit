#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p ScrollSplit.app/Contents/MacOS
cp Resources/Info.plist ScrollSplit.app/Contents/Info.plist
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -module-cache-path "${TMPDIR:-/tmp}/scrollsplit-swift-cache" \
  -framework AppKit -framework SwiftUI -framework ApplicationServices -framework ServiceManagement \
  Source/main.swift -o ScrollSplit.app/Contents/MacOS/ScrollSplit
codesign --force --sign - ScrollSplit.app
ScrollSplit.app/Contents/MacOS/ScrollSplit --self-test
echo 'Built ScrollSplit.app for Apple silicon.'
