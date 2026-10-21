#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/install.sh"
find_python
WORK=$(mktemp -d /tmp/bwh45-reality.tests.XXXXXX)
trap cleanup EXIT
printf '%s\n' '00000000-0000-4000-8000-000000000001' > "$WORK/uuid"
PRIVATE=$(printf 'A%.0s' {1..43})
PUBLIC=$(printf 'B%.0s' {1..43})
for format in old compact password decorated; do
  case "$format" in
    old) printf 'Private key: %s\nPublic key: %s\n' "$PRIVATE" "$PUBLIC";;
    compact) printf 'PrivateKey: %s\nPublicKey: %s\n' "$PRIVATE" "$PUBLIC";;
    password) printf 'PrivateKey: %s\nPassword: %s\nHash32: %s\n' "$PRIVATE" "$PUBLIC" "$PRIVATE";;
    decorated) printf 'PrivateKey: %s\r\nHash32: %s\r\nPassword (PublicKey): %s\r\n' "$PRIVATE" "$PRIVATE" "$PUBLIC";;
  esac > "$WORK/keys"
  helper state "$WORK/keys" "$WORK/uuid" 45.62.124.217 443 www.microsoft.com "$CORE_VERSION" chrome > "$WORK/state.json"
  "$PY" - "$WORK/state.json" "$PRIVATE" "$PUBLIC" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s['private']==sys.argv[2] and s['public']==sys.argv[3]
assert len(s['short_id'])==16
PY
done
printf 'PrivateKey: %s\nHash32: %s\n' "$PRIVATE" "$PUBLIC" > "$WORK/bad-keys"
if helper state "$WORK/bad-keys" "$WORK/uuid" 45.62.124.217 443 www.microsoft.com "$CORE_VERSION" chrome >"$WORK/bad-output" 2>"$WORK/bad-error"; then
  die 'Hash32 accepted as public key'
fi
[[ ! -s "$WORK/bad-output" ]]
if awk -v secret="$PRIVATE" 'index($0,secret){found=1}END{exit !found}' "$WORK/bad-error"; then die 'Private key leaked'; fi
helper server "$WORK/state.json" 0.0.0.0 443 > "$WORK/server.json"
helper client "$WORK/state.json" 45.62.124.217 443 10808 > "$WORK/client.json"
helper uri "$WORK/state.json" > "$WORK/uri"
helper text "$WORK/state.json" > "$WORK/info"
"$PY" - "$WORK" "$PRIVATE" <<'PY'
import json,os,sys
try:
    from urllib.parse import urlparse,parse_qs
except ImportError:
    from urlparse import urlparse,parse_qs
root=sys.argv[1]; s=json.load(open(os.path.join(root,'state.json')))
server=json.load(open(os.path.join(root,'server.json')))
client=json.load(open(os.path.join(root,'client.json')))
i=server['inbounds'][0]; o=client['outbounds'][0]
assert i['listen']=='0.0.0.0' and i['port']==443
assert i['settings']['clients'][0]['flow']=='xtls-rprx-vision'
assert i['streamSettings']['security']=='reality'
r=i['streamSettings']['realitySettings']
assert r['privateKey']==s['private'] and r['serverNames']==[s['sni']]
assert r['target']==s['sni']+':443'
assert o['settings']['vnext'][0]['users'][0]['flow']=='xtls-rprx-vision'
assert client['inbounds'][0]['listen']=='127.0.0.1'
assert o['streamSettings']['realitySettings']['publicKey']==s['public']
uri=open(os.path.join(root,'uri')).read().strip(); q=parse_qs(urlparse(uri).query)
assert q['type']==['tcp'] and q['security']==['reality']
assert q['fp']==['chrome'] and q['pbk']==[s['public']]
assert q['sid']==[s['short_id']]
for f in ['info','uri','client.json']:
    assert sys.argv[2] not in open(os.path.join(root,f)).read()
print('PASS: four X25519 formats, URI/config agreement, private-key isolation')
PY
for invalid in 'example.com";exit' '../example' 'a..b' '-bad.example'; do
  if helper hostname "$invalid" >/dev/null 2>&1; then die 'Unsafe hostname accepted'; fi
done
for invalid in 127.0.0.1 10.0.0.1 192.168.1.1 169.254.169.254 999.2.3.4 203.0.113.1; do
  printf '%s\n' "$invalid" > "$WORK/ip"
  if helper public-ip "$WORK/ip" >/dev/null 2>&1; then die 'Nonpublic IP accepted'; fi
done
printf '%s\n' 45.62.124.217 > "$WORK/ip"
[[ $(helper public-ip "$WORK/ip") == 45.62.124.217 ]]
printf 'State Recv-Q Send-Q Local:Port Peer:Port\nLISTEN 0 128 0.0.0.0:8443 *:*\n' > "$WORK/ss"
ss() { cat "$WORK/ss"; }
if port_busy 443; then die '8443 falsely treated as 443'; fi
printf 'LISTEN 0 128 [::]:443 [::]:*\n' >> "$WORK/ss"
port_busy 443
unset -f ss
printf 'tampered archive' > "$WORK/fake.zip"
if (
  trap - EXIT
  fetch() { cp -- "$WORK/fake.zip" "$WORK/xray.zip"; }
  download_core
) >"$WORK/checksum-output" 2>&1; then die 'Bad archive was accepted'; fi
printf '%s\n' 'PASS: unsafe input and bad checksum rejection'
CASE_DIR=$WORK/rollback
mkdir -p "$CASE_DIR"
if (
  trap - EXIT
  BASE=$CASE_DIR/config; LIB=$CASE_DIR/lib; UNIT=$CASE_DIR/test.service; INFO=$CASE_DIR/info
  mkdir -p "$BASE" "$LIB"
  printf '%s\n' "$OWNER" > "$BASE/.owner"
  printf 'test' > "$UNIT"; printf 'test' > "$INFO"
  WORK=; OWNED=1; COMMITTED=0
  systemctl() { return 0; }
  trap cleanup EXIT
  exit 7
) >/dev/null 2>&1; then die 'Rollback test unexpectedly succeeded'; else [[ $? == 7 ]]; fi
[[ ! -e "$CASE_DIR/config" && ! -e "$CASE_DIR/lib" && ! -e "$CASE_DIR/test.service" && ! -e "$CASE_DIR/info" ]]
printf '%s\n' 'PASS: failed fresh installation removes only its managed files'
bash -n "$ROOT/install.sh"
printf 'PASS: Bash %s / %s compatibility and all unit/regression checks\n' "$BASH_VERSION" "$("$PY" --version 2>&1)"
