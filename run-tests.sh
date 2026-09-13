#!/bin/bash
# Fuehrt die Testsuite auf einem Simulator aus.
#
# Mit ausdruecklichem Ziel, weil ein Name wie "iPhone 15 Pro" auf diesem Rechner
# zweimal existiert (iOS 17.5 und 18.0) und xcodebuild eine mehrdeutige Angabe
# nicht aufloest, sondern mit einem irrefuehrenden "My Mac"-Fehler abbricht.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-iPhone 17 Pro}"
ID=$(xcodebuild -project Fundus.xcodeproj -scheme Fundus -showdestinations 2>/dev/null \
  | grep "platform:iOS Simulator" | grep "name:$DEVICE }" | tail -1 \
  | sed -E 's/.*id:([0-9A-F-]+).*/\1/')
[ -n "$ID" ] || { echo "Kein Simulator namens \"$DEVICE\" gefunden."; exit 1; }

xcodegen generate >/dev/null
exec xcodebuild -project Fundus.xcodeproj -scheme Fundus \
  -destination "id=$ID" -derivedDataPath build/dd test
