#!/bin/bash
# Fuehrt die Testsuite auf einem Simulator aus.
#
# Mit ausdruecklichem Ziel, weil ein Name wie "iPhone 17 Pro" auf diesem Rechner
# mehrfach existiert (mehrere iOS-Versionen) und xcodebuild eine mehrdeutige Angabe
# nicht aufloest, sondern mit einem irrefuehrenden "My Mac"-Fehler abbricht.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-iPhone 17 Pro}"

# Die Ermittlung der Kennung steht bewusst nicht in einer einzigen Zuweisung mit
# Pipe. Mit `set -euo pipefail` bricht das Skript dann ab, sobald irgendein Glied
# der Pipe scheitert — und zwar *bevor* die Fehlermeldung darunter ausgegeben werden
# kann. Ergebnis: Exit 1 und kein Wort dazu. Genau das ist heute zweimal passiert,
# xcodebuild antwortete zwischendurch nicht, und der Lauf sah aus wie ein
# fehlgeschlagener Test.
DESTINATIONS=""
if ! DESTINATIONS=$(xcodebuild -project Fundus.xcodeproj -scheme Fundus \
                      -showdestinations 2>&1); then
  echo "xcodebuild -showdestinations ist fehlgeschlagen:" >&2
  echo "$DESTINATIONS" | tail -5 >&2
  exit 1
fi

ID=$(printf '%s\n' "$DESTINATIONS" \
     | grep "platform:iOS Simulator" \
     | grep "name:$DEVICE }" \
     | tail -1 \
     | sed -E 's/.*id:([0-9A-F-]+).*/\1/') || true

if [ -z "$ID" ]; then
  echo "Kein Simulator namens \"$DEVICE\" gefunden. Vorhanden sind:" >&2
  printf '%s\n' "$DESTINATIONS" | grep "platform:iOS Simulator" \
    | sed -E 's/.*name:([^}]+).*/  \1/' | sort -u >&2
  exit 1
fi

xcodegen generate >/dev/null
exec xcodebuild -project Fundus.xcodeproj -scheme Fundus \
  -destination "id=$ID" -derivedDataPath build/dd test
