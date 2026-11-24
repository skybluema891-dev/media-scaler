#!/bin/bash
# Inspect the two distributed containers and exercise the actual copied app.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="${EXPECTED_ARCH:?runner architecture is required}"
VERSION="${RELEASE_VERSION:?release version is required}"
test "$(uname -m)" = "$ARCH"
BASE="MediaScaler-$VERSION-macos-$ARCH"
BUILD_NUMBER="$(sed -n 's/^version: .*+\([0-9][0-9]*\)$/\1/p' pubspec.yaml)"
test -n "$BUILD_NUMBER"
SCREENSHOT="$PWD/dist/window-macos-$ARCH.png"
SCRATCH="$(mktemp -d "$PWD/build/package-audit.XXXXXX")"
MOUNT="$SCRATCH/mount"
GUI_PID=''
mounted=0
cleanup() {
  if [ -n "$GUI_PID" ]; then kill "$GUI_PID" 2>/dev/null || true; wait "$GUI_PID" || true; fi
  if [ "$mounted" -eq 1 ]; then hdiutil detach "$MOUNT" || return 1; fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT
mkdir "$MOUNT" "$SCRATCH/zip" "$SCRATCH/Applications"
ditto -x -k "dist/$BASE.zip" "$SCRATCH/zip"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "dist/$BASE.dmg"
mounted=1
test "$(readlink "$MOUNT/Applications")" = /Applications
ditto "$MOUNT/media_scaler.app" "$SCRATCH/Applications/media_scaler.app"
APP="$SCRATCH/Applications/media_scaler.app"
for package in "$APP" "$SCRATCH/zip/media_scaler.app"; do
  test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$package/Contents/Info.plist")" = "$VERSION"
  test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$package/Contents/Info.plist")" = "$BUILD_NUMBER"
  codesign --verify --deep --strict "$package"
  for program in MacOS/media_scaler Resources/tools/ffmpeg/macos/ffmpeg Resources/tools/ffmpeg/macos/ffprobe Resources/tools/ai/macos/media_ai/media_ai; do
    test -x "$package/Contents/$program"
    lipo "$package/Contents/$program" -verify_arch "$ARCH"
  done
  if [ "${REQUIRE_MACOS_NOTARIZATION:-0}" = 1 ]; then
    xcrun stapler validate "$package"
    spctl --assess --type execute "$package"
  fi
done
MEDIA_SCALER_TEST_APP="$APP/Contents/Resources" python -m unittest discover -s ai_worker -p 'test_*.py'
cd "$SCRATCH"
"$APP/Contents/MacOS/media_scaler" > "$SCRATCH/gui.log" 2>&1 &
GUI_PID=$!
# Check for a real, nonempty WindowServer window, rather than just a live PID.
window_id="$(swift - "$GUI_PID" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
for _ in 0..<40 {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows where window[kCGWindowOwnerPID as String] as? Int == pid {
        if window[kCGWindowLayer as String] as? Int == 0,
           let bounds = window[kCGWindowBounds as String] as? [String: Any],
           (bounds["Width"] as? Double ?? 0) > 200, (bounds["Height"] as? Double ?? 0) > 200 {
            print(window[kCGWindowNumber as String] as! Int)
            exit(0)
        }
    }
    Thread.sleep(forTimeInterval: 0.5)
}
exit(1)
SWIFT
)"
echo "Media Scaler window present on hosted Mac"
# Some hosted sessions restrict screen recording. Keep the window result and
# distinguish it from a reviewed screenshot in the run summary.
if ! screencapture -x -o -l "$window_id" "$SCREENSHOT" || [ ! -s "$SCREENSHOT" ]; then
  echo "::warning::Screenshot unavailable for the Media Scaler window on this runner."
fi
cd - > /dev/null
(cd dist && shasum -a 256 "$BASE.zip" "$BASE.dmg" > "SHA256SUMS-macos-$ARCH.txt")
