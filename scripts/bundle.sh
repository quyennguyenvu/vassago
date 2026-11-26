#!/bin/bash
# Builds build/Vassago.app and signs it.
#   bundle.sh install   also copies it to /Applications and launches it
#   bundle.sh dmg       also writes build/Vassago-<version>.dmg
# The release workflow sets SWIFT_BUILD_FLAGS for a universal binary.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Vassago.app
ICONSET=build/AppIcon.iconset
# shellcheck disable=SC2206  # SWIFT_BUILD_FLAGS is split into words on purpose
FLAGS=(-c release ${SWIFT_BUILD_FLAGS:-})

swift build "${FLAGS[@]}"

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$(swift build "${FLAGS[@]}" --show-bin-path)/Vassago" "$APP/Contents/MacOS/Vassago"
cp Resources/Info.plist "$APP/Contents/Info.plist"

for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" Resources/icon.svg -o "$ICONSET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/icon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Always the same certificate: macOS ties the Accessibility permission to the signer.
codesign --force --sign "Agares Dev" --identifier com.quyennguyenvu.vassago "$APP"
codesign --verify --strict --verbose=2 "$APP"

case "${1:-}" in
  install)
    pkill -x Vassago || true
    # LaunchServices keeps listing the old instance for a moment after its process is gone, and
    # "open" fails with error -600 or -609 until it stops. Waiting for the process alone is not enough.
    while [ -n "$(lsappinfo find bundleID=com.quyennguyenvu.vassago)" ]; do sleep 0.1; done
    rm -rf /Applications/Vassago.app
    cp -R "$APP" /Applications/Vassago.app
    open /Applications/Vassago.app
    ;;
  dmg)
    VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
    STAGE=build/dmg
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    # The shortcut the user drags the app onto.
    ln -s /Applications "$STAGE/Applications"
    # The mounted disk's own icon. Its "has custom icon" flag is lost unless set on the mounted
    # volume, so the image is built writable and compressed afterwards.
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
    hdiutil create -volname Vassago -srcfolder "$STAGE" -ov -format UDRW build/rw.dmg
    hdiutil attach build/rw.dmg -nobrowse -mountpoint build/mnt
    SetFile -a C build/mnt
    hdiutil detach build/mnt
    hdiutil convert build/rw.dmg -format UDZO -ov -o "build/Vassago-$VERSION.dmg"
    rm build/rw.dmg
    ;;
esac
