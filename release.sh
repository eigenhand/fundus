#!/bin/bash
# Builds Fundus and uploads it to TestFlight.
#
# Prerequisites (one-off, in App Store Connect / the Developer Portal):
#   1. Bundle ID dev.eigenhand.fundus.ios registered
#   2. App record created (name, primary language, SKU)
#   3. App Group group.dev.eigenhand.shared enabled for this bundle ID
#   4. API key with the "App Manager" role under
#      ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# Usage:  ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

[ -f .release.env ] && . ./.release.env

KEY_ID="${ASC_KEY_ID:?ASC_KEY_ID fehlt. In .release.env eintragen; die ID ist Teil des Dateinamens unter ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8}"
: "${ASC_ISSUER_ID:?Issuer ID fehlt. In .release.env eintragen. Zu finden in App Store Connect > Users and Access > Integrations > App Store Connect API, ueber der Key-Liste.}"

ARCHIVE="build/Fundus.xcarchive"
EXPORT="build/export"

# App Store Connect rejects uploads built with an Xcode beta (error 90534). If the
# active selection is a beta and a regular Xcode is installed beside it, this build
# switches over — only for this script.
if xcode-select -p | grep -qi "beta" && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  echo "==> Building with $(defaults read /Applications/Xcode.app/Contents/Info.plist CFBundleShortVersionString) instead of the beta"
fi

echo "==> Generating the project"
xcodegen generate

echo "==> Setting the build number"
BUILD=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Fundus/Info.plist

echo "==> Archiving"
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

echo "==> Checking the network"
curl -s -o /dev/null --max-time 15 https://appstoreconnect.apple.com || {
  echo "    App Store Connect is unreachable — try again later."
  exit 1
}

echo "==> Exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

# From here on without the DEVELOPER_DIR override: the detour to the regular Xcode
# applies to the build only. Its altool, by contrast, fails with
# "Defaults.properties couldn't be opened" while the beta's runs — so each tool gets
# the Xcode it works with.
unset DEVELOPER_DIR

echo "==> Validating"
xcrun altool --validate-app -f "$EXPORT/Fundus.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Uploading to TestFlight"
xcrun altool --upload-app -f "$EXPORT/Fundus.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "==> Waiting for Apple to process it, then assigning to the internal group"
./assign-build.sh "$BUILD" || {
  echo "    (assignment not completed — check in App Store Connect)"
}

echo "==> Done."
