#!/bin/bash
# Fabrique Tympan.app (et le .dmg) sans passer par un projet Xcode.
#   ./build.sh        compile et crée dist/Tympan.app (architecture du Mac)
#   ./build.sh run    idem puis lance l'app
#   ./build.sh dmg    version universelle (Apple Silicon + Intel) et dist/Tympan.dmg
#   ./build.sh appstore   version universelle signée pour l'App Store et dist/Tympan.pkg
#       TEAM_ID=XXXXXXXXXX PROFILE=chemin/Tympan.provisionprofile ./build.sh appstore
#       (identités facultatives : SIGN_ID, défaut « Apple Distribution » ;
#        INSTALLER_ID, défaut « 3rd Party Mac Developer Installer »)
set -euo pipefail
cd "$(dirname "$0")"

APP=Tympan
CMD="${1:-app}"
DIST=dist
APPDIR="$DIST/$APP.app"

ENTITLEMENTS=Support/Tympan.entitlements

if [ "$CMD" = "appstore" ]; then
  : "${TEAM_ID:?TEAM_ID manquant : identifiant équipe Apple, 10 caractères}"
  : "${PROFILE:?PROFILE manquant : profil de provisionnement Mac App Store}"
  [ -f "$PROFILE" ] || { echo "Profil introuvable : $PROFILE"; exit 1; }
fi

if [ "$CMD" = "dmg" ] || [ "$CMD" = "appstore" ]; then
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
# Migration vers le sandbox : déplace les données de l'ancienne version dans le conteneur.
cp Support/container-migration.plist "$APPDIR/Contents/Resources/"
cp Support/PrivacyInfo.xcprivacy "$APPDIR/Contents/Resources/"
if [ -f Support/AppIcon.icns ]; then
  cp Support/AppIcon.icns "$APPDIR/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APPDIR/Contents/Info.plist" 2>/dev/null || true
fi

if [ "$CMD" = "appstore" ]; then
  # Autorisations du sandbox + identité de l'app, liée au profil de provisionnement.
  SIGNED_ENTITLEMENTS="$DIST/Tympan-appstore.entitlements"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Support/Info.plist)
  cp "$ENTITLEMENTS" "$SIGNED_ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    "$SIGNED_ENTITLEMENTS"
  cp "$PROFILE" "$APPDIR/Contents/embedded.provisionprofile"
  codesign --force --sign "${SIGN_ID:-Apple Distribution}" --entitlements "$SIGNED_ENTITLEMENTS" "$APPDIR"
else
  # Signature ad hoc (gratuite) : nécessaire pour l'accès micro sur Apple Silicon.
  # Le sandbox est actif aussi en local, comme dans la version App Store.
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APPDIR"
fi
codesign --verify --strict "$APPDIR"
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
  appstore)
    rm -f "$DIST/$APP.pkg"
    productbuild --component "$APPDIR" /Applications --sign "${INSTALLER_ID:-3rd Party Mac Developer Installer}" "$DIST/$APP.pkg"
    pkgutil --check-signature "$DIST/$APP.pkg"
    echo "Paquet App Store prêt : $DIST/$APP.pkg (à envoyer avec Transporter)"
    ;;
  *)
    echo "App prête : $APPDIR"
    ;;
esac
