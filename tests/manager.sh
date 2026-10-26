#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/install.sh"
find_python
WORK=$(mktemp -d /tmp/bwh45-reality.manager-tests.XXXXXX)
trap cleanup EXIT
printf '00000000-0000-4000-8000-000000000001\n' > "$WORK/uuid"
printf 'PrivateKey: %s\nPassword (PublicKey): %s\n' "$(printf 'A%.0s' {1..43})" "$(printf 'B%.0s' {1..43})" > "$WORK/keys"
helper state "$WORK/keys" "$WORK/uuid" 45.62.124.217 443 www.amazon.com "$CORE_VERSION" chrome > "$WORK/state"
helper ss-patch "$WORK/state" on 8388 2022-blake3-aes-128-gcm '' > "$WORK/ss"
helper server "$WORK/ss" 0.0.0.0 443 > "$WORK/server"
helper ss-uri "$WORK/ss" > "$WORK/ss-uri"
helper exports "$WORK/ss" "$WORK/exports"
helper self-check
"$PY" - "$WORK" <<'PY'
import base64,json,os,sys
try:
    from urllib.parse import urlparse,unquote
except ImportError:
    from urlparse import urlparse,unquote
import xml.etree.ElementTree as ET
d=sys.argv[1];s=json.load(open(d+'/ss'));c=json.load(open(d+'/server'))
assert c['inbounds'][1]['settings']['network']=='tcp,udp'
assert c['inbounds'][1]['port']==8388
uri=open(d+'/ss-uri').read().strip()
assert uri.startswith('ss://2022-blake3-aes-128-gcm:')
assert unquote(urlparse(uri).password)==s['ss']['password']
assert len(base64.b64decode(s['ss']['password'].encode('ascii')))==16
for n in ('qr.svg','ss-qr.svg'): ET.parse(d+'/exports/'+n)
for n in ('client.json','info.txt','qr.svg','ss-client.json','ss-info.txt','ss-qr.svg'):
    assert s['private'] not in open(d+'/exports/'+n).read()
print('PASS: SS2022 URI, bundled QR SVG, two-protocol configuration, private-key isolation')
PY
printf '443\n' > "$WORK/value"
helper patch "$WORK/ss" port "$WORK/value" > "$WORK/changed"
printf '8388\n' > "$WORK/value"
if helper patch "$WORK/ss" port "$WORK/value" >/dev/null 2>&1;then die 'Protocol port collision accepted';fi
printf 'new-server\n' > "$WORK/value"
helper patch "$WORK/ss" name "$WORK/value" > "$WORK/named"
helper uri "$WORK/named" | awk '/#new-server$/{ok=1}END{exit !ok}'
LIB=$WORK/lib;LAUNCHER=$WORK/launcher;mkdir -p "$LIB"
manager_install > "$WORK/manager-install-output"
[[ -s "$LIB/manager.sh" && -x "$LAUNCHER" ]]
bash -n "$LIB/manager.sh"
[[ $(bash "$LIB/manager.sh" --version) == "$VERSION" ]]
bash "$LIB/manager.sh" --self-check
printf 'PASS: persistent manager serialization and CLI version/self-check\n'
