#!/bin/bash
# Fabrique Tympan.app (et le .dmg) sans passer par un projet Xcode.
#   ./build.sh        compile et crée dist/Tympan.app (architecture du Mac)
#   ./build.sh run    idem puis lance l'app
#   ./build.sh dmg    version universelle (Apple Silicon + Intel) et dist/Tympan.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP=Tympan
CMD="${1:-app}"
DIST=dist
APPDIR="$DIST/$APP.app"

if [ "$CMD" = "dmg" ]; then
  ARCHS=(--arch arm64 --arch x86_64)
else
  ARCHS=()
fi

echo "Compilation ($CMD)..."
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR=$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)

rm -rf "$APPDIR"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN_DIR/$APP" "$APPDIR/Contents/MacOS/$APP"
cp Support/Info.plist "$APPDIR/Contents/Info.plist"
if [ -d Localization ]; then
  cp -R Localization/*.lproj "$APPDIR/Contents/Resources/" 2>/dev/null || true
fi
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APPDIR/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APPDIR/Contents/Info.plist" 2>/dev/null || true
fi

# Signature ad hoc (gratuite) : nécessaire pour l'accès micro sur Apple Silicon.
codesign --force --deep --sign - "$APPDIR"
# Force le Finder et le Dock à relire l'icône.
touch "$APPDIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APPDIR" >/dev/null 2>&1 || true

case "$CMD" in
  run)
    open "$APPDIR"
    ;;
  dmg)
    STAGE="$DIST/dmg-stage"
    rm -rf "$STAGE" "$DIST/$APP.dmg"
    mkdir -p "$STAGE"
    cp -R "$APPDIR" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP.dmg" >/dev/null
    rm -rf "$STAGE"
    echo "DMG prêt : $DIST/$APP.dmg"
    ;;
  *)
    echo "App prête : $APPDIR"
    ;;
esac
