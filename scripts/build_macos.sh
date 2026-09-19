#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)}"
ARCH="$(uname -m)"
APP="$PWD/build/macos/Build/Products/Release/media_scaler.app"
# Local builds may use ad-hoc signing. Release builds set
# REQUIRE_MACOS_NOTARIZATION=1 and must use Developer ID + Apple notarization.
REQUIRE_NOTARIZATION="${REQUIRE_MACOS_NOTARIZATION:-0}"
IDENTITY="${MACOS_SIGN_IDENTITY:--}"
if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  if [ "$IDENTITY" = "-" ] || [ -z "$IDENTITY" ]; then
    echo "Developer ID Application identity is required for a release build." >&2
    exit 1
  fi
  for variable in NOTARY_KEY_PATH APPLE_API_KEY_ID APPLE_API_ISSUER_ID; do
    if [ -z "${!variable:-}" ]; then
      echo "$variable is required for a notarized release build." >&2
      exit 1
    fi
  done
  if [ ! -f "$NOTARY_KEY_PATH" ]; then
    echo "Notary API key was not found: $NOTARY_KEY_PATH" >&2
    exit 1
  fi
fi
flutter pub get
# Flutter 3.47's LSP client can truncate JSON messages when the project path
# contains multibyte characters. The Dart CLI performs the same source
# analysis without that transport bug.
dart analyze lib test
flutter test
# Avoid retaining bundled tools from a previous layout or build.
if [ -d "$APP" ]; then
  rm -rf "$APP"
fi
flutter build macos --release --build-name="$VERSION" \
  "--dart-define=UPDATE_REPOSITORY=${UPDATE_REPOSITORY:-}" \
  "--dart-define=UPDATE_TARGET=macos-$ARCH"
TOOLS="$APP/Contents/Resources/tools"
mkdir -p "$TOOLS/ffmpeg/macos" "$TOOLS/ai" "$APP/Contents/Resources/licenses" dist
cp -R tools/ai/macos "$TOOLS/ai/"
cp "$(command -v ffmpeg)" "$TOOLS/ffmpeg/macos/ffmpeg"
cp "$(command -v ffprobe)" "$TOOLS/ffmpeg/macos/ffprobe"
dylibbundler -cd -of -b -x "$TOOLS/ffmpeg/macos/ffmpeg" -x "$TOOLS/ffmpeg/macos/ffprobe" \
  -d "$TOOLS/ffmpeg/macos/lib" -p "@executable_path/lib/"
cp -R tools/licenses/. "$APP/Contents/Resources/licenses/"
cp THIRD_PARTY_NOTICES.txt パラメーター設定ガイド.txt "$APP/Contents/Resources/"
# Preserve Homebrew license notices for FFmpeg and its dependencies.
for formula in ffmpeg $(brew deps ffmpeg); do
  prefix="$(brew --prefix "$formula")"
  mkdir -p "$APP/Contents/Resources/licenses/$formula"
  find "$prefix" -maxdepth 1 -type f \( -iname '*license*' -o -iname '*copying*' \) \
    -exec cp '{}' "$APP/Contents/Resources/licenses/$formula/" \;
done
sign_code() {
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$1"
  fi
}
# Sign every nested Mach-O first. This includes Flutter, FFmpeg, Python worker,
# native Python modules and their relocated dynamic libraries.
while IFS= read -r -d '' file; do
  if file -b "$file" | grep -q 'Mach-O'; then
    sign_code "$file"
    codesign --verify --strict "$file"
  fi
done < <(find "$APP/Contents" -type f -print0)
# Seal nested code bundles after their binaries, from the deepest bundle out.
while IFS= read -r -d '' bundle; do
  sign_code "$bundle"
done < <(find "$APP/Contents" -depth -type d \
  \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) -print0)
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$APP"
else
  codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements macos/Runner/Release.entitlements "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
# Verify relocated dependencies before making an artifact.
test -x "$APP/Contents/MacOS/media_scaler"
test -x "$TOOLS/ffmpeg/macos/ffmpeg"
test -x "$TOOLS/ffmpeg/macos/ffprobe"
test -x "$TOOLS/ai/macos/media_ai/media_ai"
"$TOOLS/ffmpeg/macos/ffmpeg" -version
"$TOOLS/ai/macos/media_ai/media_ai" --help

notarize() {
  local upload="$1"
  local result="$2"
  xcrun notarytool submit "$upload" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait --output-format json > "$result"
  python3 -c 'import json, sys; data=json.load(open(sys.argv[1])); assert data.get("status") == "Accepted", data' "$result"
}

if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  ditto -c -k --keepParent "$APP" dist/notarize.zip
  notarize dist/notarize.zip dist/notarize-app-result.json
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=4 "$APP"
fi

# Reproduce a Finder copy into an Applications-style directory and verify that
# no sealed resources, executable bits, or relative paths are lost.
RELOCATION_ROOT="$PWD/build/relocation-test/Applications"
RELOCATED_APP="$RELOCATION_ROOT/media_scaler.app"
rm -rf "$RELOCATION_ROOT"
mkdir -p "$RELOCATION_ROOT"
ditto "$APP" "$RELOCATED_APP"
codesign --verify --deep --strict --verbose=2 "$RELOCATED_APP"
test -x "$RELOCATED_APP/Contents/MacOS/media_scaler"
"$RELOCATED_APP/Contents/Resources/tools/ffmpeg/macos/ffmpeg" -version
"$RELOCATED_APP/Contents/Resources/tools/ai/macos/media_ai/media_ai" --help
if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  xcrun stapler validate "$RELOCATED_APP"
  spctl --assess --type execute --verbose=4 "$RELOCATED_APP"
fi

ditto -c -k --keepParent "$APP" "dist/MediaScaler-$VERSION-macos-$ARCH.zip"
STAGING="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="dist/MediaScaler-$VERSION-macos-$ARCH.dmg"
hdiutil create -volname "Media Scaler" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
if [ "$REQUIRE_NOTARIZATION" = "1" ]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
  notarize "$DMG" dist/notarize-dmg-result.json
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
fi
