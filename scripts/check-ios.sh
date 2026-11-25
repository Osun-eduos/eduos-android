#!/usr/bin/env bash
# Builds the iOS app on a Mac without code signing, to check the iOS project compiles.
# Needs Xcode (with command-line tools), CocoaPods and Flutter 3.47. Writes everything to ios-build.log.
set -uo pipefail
cd "$(dirname "$0")/.."
log=ios-build.log
{
  echo "== $(date)"
  sw_vers; xcodebuild -version; pod --version; flutter --version
  flutter pub get
  flutter build ios --release --no-codesign
  echo "== exit $?"
} > "$log" 2>&1
tail -5 "$log"
echo "Full log: $(pwd)/$log"
