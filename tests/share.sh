#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/install.sh"
find_python
WORK=$(mktemp -d /tmp/bwh45-reality.share-test.XXXXXX)
trap cleanup EXIT
BASE=$WORK/base
mkdir -p "$BASE"
sharing_certificate 127.0.0.1
printf '00000000-0000-4000-8000-000000000001\n' > "$WORK/uuid"
printf 'PrivateKey: %s\nPassword (PublicKey): %s\n' "$(printf 'A%.0s' {1..43})" "$(printf 'B%.0s' {1..43})" > "$WORK/keys"
helper state "$WORK/keys" "$WORK/uuid" 45.62.124.217 443 www.amazon.com "$CORE_VERSION" chrome > "$WORK/state"
folder=$BASE/export
helper exports "$WORK/state" "$folder"
number=$(helper free-port)
helper make-share 127.0.0.1 "$number" "$folder" 8 "$SHARE_CRT" "$SHARE_PRIV" > "$BASE/share.json"
token=$(helper meta-field "$BASE/share.json" token)
helper serve-share "$BASE/share.json" > "$WORK/server.log" 2>&1 &
SERVER_PID=$!
wait_listener "$number" "$SERVER_PID"
curl -fsS --noproxy '*' --cacert "$BASE/share-tls/ca.pem" "https://127.0.0.1:$number/$token/client.json" -o "$WORK/download"
code=$(curl -sS --noproxy '*' --cacert "$BASE/share-tls/ca.pem" -o /dev/null -w '%{http_code}' "https://127.0.0.1:$number/$token/state.json")
[[ "$code" == 404 ]]
"$PY" - "$WORK/download" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert c['outbounds'][0]['protocol']=='vless'
PY
printf 'GET /%s/client.json HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n' "$token" |
  timeout 5 openssl s_client -quiet -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 \
    -verify_return_error -connect "127.0.0.1:$number" -CAfile "$BASE/share-tls/ca.pem" > "$WORK/ecdhe-response" 2>"$WORK/ecdhe-log" || true
awk '/^HTTP\/1.0 200/{ok=1}END{exit !ok}' "$WORK/ecdhe-response" || { cat "$WORK/ecdhe-log" >&2;die 'Verified ECDHE HTTPS request failed'; }
sleep 9
if kill -0 "$SERVER_PID" 2>/dev/null;then die 'Expired sharing server remained running';fi
wait "$SERVER_PID"
SERVER_PID=
say "PASS: trusted-certificate HTTPS export, path allowlist and expiry ($("$PY" --version 2>&1))"
