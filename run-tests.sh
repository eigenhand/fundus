#!/bin/bash
# Runs the test suite on a simulator.
#
# With an explicit destination, because a name like "iPhone 17 Pro" exists several
# times over on this machine (several iOS versions) and xcodebuild does not resolve an
# ambiguous one but fails with a misleading "My Mac" error.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-iPhone 17 Pro}"

# Looking the identifier up is deliberately not one single assignment with a pipe.
# With `set -euo pipefail` the script then aborts as soon as any link in the pipe
# fails — and *before* the error message below it can be printed. The result: exit 1
# and not a word about it. That happened twice in one day, xcodebuild stopped
# answering in between, and the run looked like a failed test.
DESTINATIONS=""
if ! DESTINATIONS=$(xcodebuild -project Fundus.xcodeproj -scheme Fundus \
                      -showdestinations 2>&1); then
  echo "xcodebuild -showdestinations failed:" >&2
  echo "$DESTINATIONS" | tail -5 >&2
  exit 1
fi

ID=$(printf '%s\n' "$DESTINATIONS" \
     | grep "platform:iOS Simulator" \
     | grep "name:$DEVICE }" \
     | tail -1 \
     | sed -E 's/.*id:([0-9A-F-]+).*/\1/') || true

if [ -z "$ID" ]; then
  echo "No simulator called \"$DEVICE\" found. Available:" >&2
  printf '%s\n' "$DESTINATIONS" | grep "platform:iOS Simulator" \
    | sed -E 's/.*name:([^}]+).*/  \1/' | sort -u >&2
  exit 1
fi

xcodegen generate >/dev/null
exec xcodebuild -project Fundus.xcodeproj -scheme Fundus \
  -destination "id=$ID" -derivedDataPath build/dd test
