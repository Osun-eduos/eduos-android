#!/usr/bin/env bash
# Builds the iOS app on a Mac without code signing, to check the iOS project compiles.
# Needs Xcode (with command-line tools), CocoaPods and Flutter 3.47 (see README, iOS). Writes everything to ios-build.log.
set -uo pipefail
cd "$(dirname "$0")/.."
log=ios-build.log
# EduOS needs Flutter 3.47. Use a separate copy in ~/flutter-eduos if present (or $FLUTTER), so other projects
# keep their own Flutter version.
if [ -n "${FLUTTER:-}" ]; then :; elif [ -x "$HOME/flutter-eduos/bin/flutter" ]; then FLUTTER="$HOME/flutter-eduos/bin/flutter"; else FLUTTER=flutter; fi
{
  echo "== $(date)"
  sw_vers; xcodebuild -version; pod --version; "$FLUTTER" --version
  "$FLUTTER" pub get
  "$FLUTTER" build ios --release --no-codesign
  echo "== exit $?"
} > "$log" 2>&1
tail -5 "$log"
echo "Full log: $(pwd)/$log"
