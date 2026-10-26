#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/install.sh"
find_python
WORK=$(mktemp -d /tmp/bwh45-reality.network.XXXXXX)
trap cleanup EXIT
download_core
ADDRESS=45.62.124.217
PORT=443
"$XRAY" uuid > "$WORK/uuid"
"$XRAY" x25519 > "$WORK/keys"
choose_target
helper server "$WORK/state.json" 0.0.0.0 443 > "$WORK/export-server.json"
helper client "$WORK/state.json" "$ADDRESS" 443 10808 > "$WORK/export-client.json"
"$XRAY" run -test -config "$WORK/export-server.json"
"$XRAY" run -test -config "$WORK/export-client.json"
"$PY" - "$WORK/state.json" "$WORK/ios-state.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]));s['fp']='ios'
with open(sys.argv[2],'w') as f: json.dump(s,f)
PY
test_port=$(helper free-port)
test_proxy "$WORK/ios-state.json" "$test_port" 1
helper ss-patch "$WORK/state.json" on 8388 2022-blake3-aes-128-gcm '' > "$WORK/ss.json"
test_port=$(helper free-port)
ss_proxy_test "$WORK/ss.json" "$test_port" 1
printf 'PASS: actual official Xray REALITY/Vision end-to-end with chrome and ios (%s)\n' "$("$PY" --version 2>&1)"
