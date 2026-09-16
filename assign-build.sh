#!/bin/bash
# Waits until App Store Connect has processed a build, then puts it into the
# internal tester group. Without this step a build is uploaded but visible to
# nobody.
#
# Aufruf:  ./assign-build.sh <CFBundleVersion>
set -euo pipefail
cd "$(dirname "$0")"
[ -f .release.env ] && . ./.release.env
: "${ASC_ISSUER_ID:?Issuer ID fehlt (.release.env)}"

APP_ID="6811630235"
WANTED="${1:?Build-Nummer angeben}"

token() { ./asc-token.sh; }

echo "    waiting for $WANTED to be processed …"
BUILD_ID=""
for i in $(seq 1 60); do
  T=$(token)
  read -r STATE ID <<<"$(curl -s -H "Authorization: Bearer $T" \
    "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=$APP_ID&limit=5&sort=-uploadedDate" \
    | python3 -c "
import json,sys
for b in json.load(sys.stdin).get('data',[]):
    if b['attributes'].get('version')=='$WANTED':
        print(b['attributes'].get('processingState'), b['id']); break
else: print('PENDING none')
")"
  case "$STATE" in
    VALID)   BUILD_ID="$ID"; echo "    processed after ~$((i*30))s"; break ;;
    INVALID) echo "    Apple rejected the build."; exit 1 ;;
  esac
  sleep 30
done
[ -n "$BUILD_ID" ] || { echo "    Timed out waiting."; exit 1; }

T=$(token)
GROUP=$(curl -s -H "Authorization: Bearer $T" \
  "https://api.appstoreconnect.apple.com/v1/betaGroups?filter%5Bapp%5D=$APP_ID&limit=10" \
  | python3 -c "
import json,sys
for g in json.load(sys.stdin).get('data',[]):
    if g['attributes'].get('isInternalGroup'): print(g['id']); break
")

# On an app's very first release there is no group yet — breaking off here would mean
# uploading the build and then leaving it lying where nobody can see it. So create one
# rather than report.
if [ -z "$GROUP" ]; then
  echo "    No internal group — creating \"Intern\"."
  T=$(token)
  GROUP=$(curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    "https://api.appstoreconnect.apple.com/v1/betaGroups" \
    -d "{\"data\":{\"type\":\"betaGroups\",\"attributes\":{\"name\":\"Intern\",\"isInternalGroup\":true},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'errors' in d:
    for e in d['errors']: print('', e.get('detail') or e.get('title'), file=sys.stderr)
else: print(d['data']['id'])
")
fi
[ -n "$GROUP" ] || { echo "    No internal group, and creating one failed."; exit 1; }

CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  "https://api.appstoreconnect.apple.com/v1/betaGroups/$GROUP/relationships/builds" \
  -d "{\"data\":[{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}]}")
[ "$CODE" = "204" ] || { echo "    Assignment failed (HTTP $CODE)"; exit 1; }

sleep 2
T=$(token)
curl -s -H "Authorization: Bearer $T" \
  "https://api.appstoreconnect.apple.com/v1/builds/$BUILD_ID/buildBetaDetail" \
  | python3 -c "
import json,sys
a=json.load(sys.stdin).get('data',{}).get('attributes',{})
print('    Build $WANTED ist', a.get('internalBuildState'))
"
