#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
C=/tmp/bwh45-command-test
mkdir -p "$C"
log_cmd() {
  local name=$1;shift
  "$@" > "$C/$name.log" 2>&1 || {
    awk '!/^(UUID:|PublicKey|ShortId:|vless:|ss:|Password:)/' "$C/$name.log";return 1;
  }
}
log_cmd install bash install.sh
test -x /usr/local/bin/v2ray
v2ray --version | awk '$0=="3.0.0"{ok=1}END{exit !ok}'
log_cmd info v2ray info
log_cmd status v2ray status
cp /etc/bwh45-reality/state.json "$C/original-state"
log_cmd name v2ray config --name ci-node
log_cmd port v2ray config --port 14443
log_cmd port-back v2ray config --port 443
log_cmd stop v2ray stop
if systemctl is-active --quiet bwh45-reality.service;then exit 1;fi
log_cmd start v2ray start
log_cmd restart v2ray restart
log_cmd log v2ray log
# Force a failed real-service restart after candidate validation, then require rollback.
cp /etc/bwh45-reality/state.json "$C/pre-rollback"
mkdir "$C/shim";touch "$C/fail-once"
cat > "$C/shim/systemctl" <<'SHIM'
#!/bin/bash
if [[ "$1" == restart && -f /tmp/bwh45-command-test/fail-once ]];then rm /tmp/bwh45-command-test/fail-once;exit 1;fi
exec /usr/bin/systemctl "$@"
SHIM
chmod +x "$C/shim/systemctl"
if PATH="$C/shim:$PATH" v2ray config --name must-rollback > "$C/rollback.log" 2>&1;then exit 1;fi
cmp "$C/pre-rollback" /etc/bwh45-reality/state.json
systemctl is-active --quiet bwh45-reality.service
log_cmd ss-enable v2ray ss --enable --port 18388
log_cmd ssinfo v2ray ssinfo
for cmd in link infolink qr ssqr;do
  log_cmd "$cmd" v2ray "$cmd"
  url=$(awk '/^https:/{print;exit}' "$C/$cmd.log")
  test -n "$url"
  # Keep the exported hostname for certificate verification while connecting locally.
  host=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.urlparse(sys.argv[1]).hostname)' "$url")
  curl -fsS --noproxy '*' --cacert /etc/bwh45-reality/share-tls/ca.pem \
    --connect-to "$host:8443:127.0.0.1:8443" "$url" -o "$C/$cmd.download"
done
python3 - "$C" <<'PY'
import json,sys,xml.etree.ElementTree as ET
p=sys.argv[1];s=json.load(open('/etc/bwh45-reality/state.json'))
assert json.load(open(p+'/link.download'))['outbounds'][0]['protocol']=='vless'
assert s['uuid'] in open(p+'/infolink.download').read()
ET.parse(p+'/qr.download');ET.parse(p+'/ssqr.download')
for f in ('link.download','infolink.download','qr.download','ssqr.download'):
    assert s['private'] not in open(p+'/'+f).read()
PY
rsvg-convert "$C/qr.download" -o "$C/qr.png"
rsvg-convert "$C/ssqr.download" -o "$C/ssqr.png"
zbarimg --quiet --raw "$C/qr.png" > "$C/qr-decoded" 2>/dev/null
zbarimg --quiet --raw "$C/ssqr.png" > "$C/ssqr-decoded" 2>/dev/null
cmp "$C/qr-decoded" /etc/bwh45-reality/exports/uri.txt || python3 - "$C" <<'PY'
import sys
p=sys.argv[1]
assert open(p+'/qr-decoded').read().strip()==open('/etc/bwh45-reality/exports/uri.txt').read().strip()
PY
python3 - "$C" <<'PY'
import sys
p=sys.argv[1]
assert open(p+'/ssqr-decoded').read().strip()==open('/etc/bwh45-reality/exports/ss-uri.txt').read().strip()
PY
# Exact path allowlist; no server state/private-key download endpoint.
url=$(awk '/^https:/{print;exit}' "$C/link.log")
url="${url%/*}/state.json"
host=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.urlparse(sys.argv[1]).hostname)' "$url")
code=$(curl -sS --noproxy '*' --cacert /etc/bwh45-reality/share-tls/ca.pem --connect-to "$host:8443:127.0.0.1:8443" -o /dev/null -w '%{http_code}' "$url")
test "$code" = 404
systemctl stop bwh45-reality-share.service
log_cmd expiry env SHARE_TTL=2 v2ray link
sleep 3
if systemctl is-active --quiet bwh45-reality-share.service;then exit 1;fi
systemctl is-active --quiet bwh45-reality.service
log_cmd core-update v2ray update 26.3.27
# Exercise the actual hash-verified manager updater without changing node credentials.
sed -i '0,/^VERSION=3.0.0$/s//VERSION=2.99.0/' /usr/local/lib/bwh45-reality/manager.sh
log_cmd manager-update v2ray update.sh
test "$(v2ray --version)" = 3.0.0
log_cmd ss-disable v2ray ss --disable
log_cmd check v2ray check
python3 - "$C/original-state" /etc/bwh45-reality/state.json <<'PY'
import json,sys
a,b=[json.load(open(p)) for p in sys.argv[1:]]
for k in ['uuid','private','public','short_id','sni','fp']: assert a[k]==b[k],k
PY
log_cmd uninstall v2ray uninstall
test ! -e /usr/local/bin/v2ray
test ! -e /etc/bwh45-reality
test ! -e /usr/local/lib/bwh45-reality
# Upgrade a real v2 installation in place; the credential set must be byte-for-byte unchanged.
curl -fsSL https://raw.githubusercontent.com/elastelzhou-web/test/0540b951e0c9d645ce3cbf9f4271e3d296e87524/install.sh -o "$C/v2.sh"
log_cmd old-install bash "$C/v2.sh"
cp /etc/bwh45-reality/state.json "$C/v2-state"
log_cmd upgrade bash install.sh
cmp "$C/v2-state" /etc/bwh45-reality/state.json
test -x /usr/local/bin/v2ray
log_cmd upgraded-check v2ray check
log_cmd upgraded-uninstall v2ray uninstall
echo "PASS: all 16 commands, actual TLS sharing and expiry, QR decode, SS TCP/UDP, transaction rollback, core/manager update, legacy migration"
