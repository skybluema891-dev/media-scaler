#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)}"
ARCH="$(uname -m)"
APP="$PWD/build/macos/Build/Products/Release/media_scaler.app"
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
# Ad-hoc signing permits local testing; Developer ID and notarization are optional.
IDENTITY="${MACOS_SIGN_IDENTITY:--}"
sign_code() {
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$1"
  else
    codesign --force --sign "$IDENTITY" --options runtime "$1"
  fi
}
find "$TOOLS" -type f -print0 | while IFS= read -r -d '' file; do
  if file -b "$file" | grep -q 'Mach-O'; then
    sign_code "$file"
    codesign --verify --strict "$file"
  fi
done
# Do not use --deep here: PyInstaller includes *.dist-info metadata directories
# that codesign may misclassify as malformed nested bundles. Nested Mach-O files
# are explicitly signed and verified above, then the outer app seal is created.
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$APP"
else
  codesign --force --sign "$IDENTITY" --options runtime \
    --entitlements macos/Runner/Release.entitlements "$APP"
fi
codesign --verify --strict "$APP"
# Verify relocated dependencies before making an artifact.
"$TOOLS/ffmpeg/macos/ffmpeg" -version
"$TOOLS/ai/macos/media_ai/media_ai" --help
if [ -n "${NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$APP" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi
ditto -c -k --keepParent "$APP" "dist/MediaScaler-$VERSION-macos-$ARCH.zip"
STAGING="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Media Scaler" -srcfolder "$STAGING" -ov -format UDZO \
  "dist/MediaScaler-$VERSION-macos-$ARCH.dmg"
rm -rf "$STAGING"
