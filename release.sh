#!/bin/bash
# Baut Fundus und laedt es zu TestFlight.
#
# Einmalige Voraussetzungen (in App Store Connect / im Developer-Portal):
#   1. Bundle-ID dev.eigenhand.fundus.ios registriert
#   2. App-Eintrag angelegt (Name, Primaersprache, SKU)
#   3. App Group group.dev.eigenhand.shared fuer diese Bundle-ID freigeschaltet
#   4. API-Key mit der Rolle "App Manager" unter
#      ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# Aufruf:  ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

[ -f .release.env ] && . ./.release.env

KEY_ID="${ASC_KEY_ID:?ASC_KEY_ID fehlt. In .release.env eintragen; die ID ist Teil des Dateinamens unter ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8}"
: "${ASC_ISSUER_ID:?Issuer ID fehlt. In .release.env eintragen. Zu finden in App Store Connect > Users and Access > Integrations > App Store Connect API, ueber der Key-Liste.}"

ARCHIVE="build/Fundus.xcarchive"
EXPORT="build/export"

# App Store Connect lehnt Uploads ab, die mit einer Xcode-Beta gebaut wurden
# (Fehler 90534). Ist die aktive Auswahl eine Beta und daneben ein regulaeres
# Xcode installiert, wird fuer diesen Build umgeschaltet — nur fuer dieses Skript.
if xcode-select -p | grep -qi "beta" && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  echo "==> Baue mit $(defaults read /Applications/Xcode.app/Contents/Info.plist CFBundleShortVersionString) statt der Beta"
fi

echo "==> Projekt erzeugen"
xcodegen generate

echo "==> Build-Nummer setzen"
BUILD=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Fundus/Info.plist

echo "==> Archivieren"
xcodebuild -project Fundus.xcodeproj -scheme Fundus \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath build/dd \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

echo "==> Netz pruefen"
curl -s -o /dev/null --max-time 15 https://appstoreconnect.apple.com || {
  echo "    App Store Connect ist nicht erreichbar — spaeter erneut versuchen."
  exit 1
}

echo "==> Exportieren"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

# Ab hier ohne DEVELOPER_DIR-Override: der Umweg auf das regulaere Xcode gilt nur
# fuer den Build. Dessen altool bricht dagegen mit "Defaults.properties couldn't be
# opened" ab, waehrend das der Beta laeuft — also bekommt jedes Werkzeug das Xcode,
# mit dem es funktioniert.
unset DEVELOPER_DIR

echo "==> Vorab pruefen"
xcrun altool --validate-app -f "$EXPORT/Fundus.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Zu TestFlight hochladen"
xcrun altool --upload-app -f "$EXPORT/Fundus.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Warte auf Apples Verarbeitung und weise der internen Gruppe zu"
./assign-build.sh "$BUILD" || {
  echo "    (Zuweisung nicht abgeschlossen — in App Store Connect nachsehen)"
}

echo "==> Fertig."
