#!/usr/bin/env bash
# bwh45 REALITY installer 2.0.0. Independent implementation; see README.md.
# CentOS 7 / Bash 4.2 / Python 2.7+; official, checksum-pinned Xray.
set -Eeuo pipefail
umask 077
export LC_ALL=C
CORE_VERSION=26.3.27
CORE_SHA256=23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
BASE=/etc/bwh45-reality
LIB=/usr/local/lib/bwh45-reality
BIN=$LIB/xray
STATE=$BASE/state.json
CONFIG=$BASE/config.json
INFO=/root/bwh45-reality-client.txt
UNIT=/etc/systemd/system/bwh45-reality.service
SERVICE=bwh45-reality.service
OWNER=bwh45-reality-v2
PORT=${PORT:-443}
FINGERPRINT=${FINGERPRINT:-chrome}
WORK= PY= XRAY= SERVER_PID= CLIENT_PID= OWNED=0 COMMITTED=0
FW_KIND= FW_ZONE= FW_RUNTIME=0 FW_PERMANENT=0 FW_ADDED=0
say() { printf '%s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
fetch() {
  curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 2 \
    --retry-delay 1 --connect-timeout 10 --max-time 150 "$@"
}
find_python() {
  local p
  for p in python3 python2 python; do
    if command -v "$p" >/dev/null 2>&1 &&
       "$p" -c 'import sys; assert sys.version_info >= (2,7)' 2>/dev/null; then
      PY=$p; return 0
    fi
  done
  die 'Python 2.7 or Python 3 is required. CentOS 7 normally includes Python 2.7.'
}
helper() {
 "$PY" - "$@" <<'PY_HELPER'
from __future__ import print_function
import base64, binascii, json, os, re, socket, struct, sys, uuid, zipfile
try:
    from urllib.parse import urlencode
except ImportError:
    from urllib import urlencode

def ipv4(value):
    if not re.match(r'^\d{1,3}(\.\d{1,3}){3}$', value):
        raise ValueError('Not an IPv4 address')
    nums = list(map(int, value.split('.')))
    if any(x > 255 for x in nums):
        raise ValueError('Invalid IPv4 address')
    return sum(n << (24-8*i) for i,n in enumerate(nums))

def public4(value):
    n = ipv4(value)
    blocked = [('0.0.0.0',8),('10.0.0.0',8),('100.64.0.0',10),
        ('127.0.0.0',8),('169.254.0.0',16),('172.16.0.0',12),
        ('192.0.0.0',24),('192.0.2.0',24),('192.168.0.0',16),
        ('198.18.0.0',15),('198.51.100.0',24),('203.0.113.0',24),
        ('224.0.0.0',4),('240.0.0.0',4)]
    if any(n >> (32-bits) == ipv4(net) >> (32-bits) for net,bits in blocked):
        raise ValueError('A public unicast IPv4 address is required')
    return value

def hostname(value):
    if len(value)>253 or not all(re.match(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$', x)
                                 for x in value.split('.')):
        raise ValueError('Invalid hostname')
    return value.lower()

def port(value):
    value=int(value)
    if not 1 <= value <= 65535:
        raise ValueError('Invalid TCP port')
    return value

def key(value):
    if not re.match(r'^[A-Za-z0-9_-]{43}$',value):
        raise ValueError('Invalid X25519 key')
    if len(base64.urlsafe_b64decode(value+'='))!=32:
        raise ValueError('Invalid X25519 key length')
    return value

def read_state(path):
    with open(path) as f:
        s=json.load(f)
    if s.get('owner')!='bwh45-reality-v2' or s.get('schema')!=1:
        raise ValueError('Unknown state ownership/schema')
    key(s['private']); key(s['public'])
    if str(uuid.UUID(s['uuid']))!=s['uuid']:
        raise ValueError('Invalid UUID')
    if not re.match(r'^[0-9a-f]{16}$',s['short_id']):
        raise ValueError('Invalid ShortId')
    hostname(s['sni']); port(s['port'])
    if s['fp'] not in ('chrome','ios'):
        raise ValueError('Unsupported fingerprint')
    hostname(s['address'])
    return s

def emit(obj):
    print(json.dumps(obj,sort_keys=True,indent=2))

def server(s,listen,number):
    return {'log':{'loglevel':'warning'},'inbounds':[{
        'listen':listen,'port':port(number),'protocol':'vless',
        'settings':{'clients':[{'id':s['uuid'],'flow':'xtls-rprx-vision'}],
                    'decryption':'none'},
        'streamSettings':{'network':'tcp','security':'reality',
            'realitySettings':{'show':False,'target':s['sni']+':443','xver':0,
                'serverNames':[s['sni']],'privateKey':s['private'],
                'shortIds':[s['short_id']]}}}],
        'outbounds':[{'protocol':'freedom','tag':'direct'}]}

def client(s,address,remote_port,socks_port):
    return {'log':{'loglevel':'warning'},'inbounds':[{
        'listen':'127.0.0.1','port':port(socks_port),'protocol':'socks',
        'settings':{'auth':'noauth','udp':False}}],
        'outbounds':[{'protocol':'vless','settings':{'vnext':[{
            'address':address,'port':port(remote_port),'users':[{
                'id':s['uuid'],'encryption':'none','flow':'xtls-rprx-vision'}]}]},
            'streamSettings':{'network':'tcp','security':'reality',
                'realitySettings':{'serverName':s['sni'],'fingerprint':s['fp'],
                    'publicKey':s['public'],'shortId':s['short_id'],'spiderX':'/'}}}]}

def link(s):
    query=[('encryption','none'),('flow','xtls-rprx-vision'),('security','reality'),
        ('sni',s['sni']),('fp',s['fp']),('pbk',s['public']),('sid',s['short_id']),
        ('type','tcp'),('headerType','none'),('spx','/')]
    return 'vless://%s@%s:%s?%s#bwh45-REALITY' % (
        s['uuid'],s['address'],s['port'],urlencode(query))

def main():
    op=sys.argv[1]; a=sys.argv[2:]
    if op=='public-ip':
        with open(a[0]) as f: data=f.read()
        for candidate in re.findall(r'(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?![\d.])',data):
            try:
                print(public4(candidate)); return
            except ValueError: pass
        raise ValueError('No public IPv4 found')
    if op=='address':
        value=hostname(a[0]); expected=public4(a[1])
        addresses=set(x[4][0] for x in socket.getaddrinfo(value,443,socket.AF_INET,socket.SOCK_STREAM))
        if expected not in addresses:
            raise ValueError('SERVER_ADDRESS does not resolve to this VPS public IPv4')
        print(value); return
    if op=='hostname':
        print(hostname(a[0])); return
    if op=='resolve':
        addresses=sorted(set(x[4][0] for x in socket.getaddrinfo(hostname(a[0]),443,socket.AF_INET,socket.SOCK_STREAM)))
        for ip in addresses:
            print(public4(ip))
        return
    if op=='free-port':
        sock=socket.socket(); sock.bind(('127.0.0.1',0))
        print(sock.getsockname()[1]); sock.close(); return
    if op=='listening':
        sock=socket.socket(); sock.settimeout(0.3)
        try: sock.connect(('127.0.0.1',port(a[0])))
        finally: sock.close()
        return
    if op=='extract':
        with zipfile.ZipFile(a[0]) as archive:
            data=archive.read('xray')
        with open(a[1],'wb') as f: f.write(data)
        return
    if op=='state':
        with open(a[0]) as f: output=f.read()
        fields={}
        for line in output.splitlines():
            if ':' not in line: continue
            label,value=line.split(':',1)
            label=re.sub(r'[\s_-]+','',label).lower()
            if label in ('privatekey','publickey','password','password(publickey)'):
                if label in fields: raise ValueError('Duplicate key label')
                fields[label]=value.strip()
        private=key(fields.get('privatekey',''))
        public=key(fields.get('password(publickey)',fields.get('password',fields.get('publickey',''))))
        with open(a[1]) as f: ident=str(uuid.UUID(f.read().strip()))
        fp=a[6]
        if fp not in ('chrome','ios'): raise ValueError('Unsupported fingerprint')
        emit({'schema':1,'owner':'bwh45-reality-v2','uuid':ident,'private':private,
              'public':public,'short_id':binascii.hexlify(os.urandom(8)).decode('ascii'),
              'address':hostname(a[2]),'port':port(a[3]),'sni':hostname(a[4]),
              'core_version':a[5],'fp':fp})
        return
    s=read_state(a[0])
    if op=='server': emit(server(s,a[1],a[2]))
    elif op=='client': emit(client(s,a[1],a[2],a[3]))
    elif op=='uri': print(link(s))
    elif op=='field':
        if a[1] not in ('address','port','sni','fp','core_version'):
            raise ValueError('Not a printable field')
        print(s[a[1]])
    elif op=='text':
        for label,value in [('Server',s['address']),('Port',s['port']),('Protocol','VLESS'),
            ('Transport','TCP'),('Security','REALITY'),('Flow','xtls-rprx-vision'),
            ('SNI',s['sni']),('Fingerprint',s['fp']),('UUID',s['uuid']),
            ('PublicKey (Password)',s['public']),('ShortId',s['short_id'])]:
            print('%s: %s' % (label,value))
        print('\nImport this complete line into v2rayN:\n'+link(s))
    else: raise ValueError('Unknown helper operation')
try:
    main()
except Exception as exc:
    # Do not echo input data or tracebacks containing configuration/keys.
    sys.stderr.write('Validation failed: '+str(exc)+'\n')
    sys.exit(1)
PY_HELPER
}
stop_pair() {
  local pid
  for pid in "$CLIENT_PID" "$SERVER_PID"; do
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  CLIENT_PID= SERVER_PID=
}
save_iptables() {
  if systemctl is-active --quiet iptables.service && [[ -x /etc/init.d/iptables ]]; then
    /etc/init.d/iptables save >/dev/null
  fi
}
undo_firewall() {
  case "$FW_KIND" in
    firewalld)
      [[ "$FW_RUNTIME" == 0 ]] || firewall-cmd --zone="$FW_ZONE" --remove-port="$PORT/tcp" >/dev/null 2>&1 || true
      [[ "$FW_PERMANENT" == 0 ]] || firewall-cmd --permanent --zone="$FW_ZONE" --remove-port="$PORT/tcp" >/dev/null 2>&1 || true ;;
    iptables)
      if [[ "$FW_ADDED" == 1 ]]; then
        iptables -D INPUT -p tcp --dport "$PORT" -m comment --comment "$OWNER" -j ACCEPT 2>/dev/null || true
        save_iptables || true
      fi ;;
    ufw)
      [[ "$FW_ADDED" == 0 ]] || ufw --force delete allow "$PORT/tcp" >/dev/null 2>&1 || true ;;
  esac
}
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  stop_pair
  if [[ "$OWNED" == 1 && "$COMMITTED" == 0 ]]; then
    say 'Rolling back this incomplete installation.' >&2
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE" >/dev/null 2>&1 || true
    rm -f -- "$UNIT" "$INFO"
    if [[ -f "$BASE/.owner" && $(cat "$BASE/.owner") == "$OWNER" ]]; then rm -rf -- "$BASE" "$LIB"; fi
    systemctl daemon-reload >/dev/null 2>&1 || true
    undo_firewall
  fi
  if [[ -n "$WORK" && "$WORK" == /tmp/bwh45-reality.* && -d "$WORK" ]]; then rm -rf -- "$WORK"; fi
  if [[ "$rc" != 0 ]]; then
    printf '\nInstallation/check failed; no success has been reported. Review the stage printed above.\n' >&2
  fi
  exit "$rc"
}
port_busy() {
  ss -lnt | awk -v end=":$1$" 'NR>1 && $4 ~ end {found=1} END {exit !found}'
}
wait_listener() {
  local number=$1 pid=$2 n
  for n in {1..50}; do
    kill -0 "$pid" 2>/dev/null || return 1
    if helper listening "$number" >/dev/null 2>&1; then return 0; fi
    sleep 0.2
  done
  return 1
}
download_core() {
  local archive=$WORK/xray.zip actual
  fetch "https://github.com/XTLS/Xray-core/releases/download/v$CORE_VERSION/Xray-linux-64.zip" -o "$archive"
  actual=$(sha256sum "$archive" | awk '{print $1}')
  [[ "$actual" == "$CORE_SHA256" ]] || die 'Official Xray archive SHA256 mismatch.'
  helper extract "$archive" "$WORK/xray"
  chmod 700 "$WORK/xray"
  XRAY=$WORK/xray
  "$XRAY" version
}
public_address() {
  local url candidate
  for url in https://api.ipify.org https://ipv4.icanhazip.com https://checkip.amazonaws.com; do
    if fetch -4 --noproxy '*' --max-time 12 "$url" -o "$WORK/public-ip" &&
       candidate=$(helper public-ip "$WORK/public-ip" 2>/dev/null); then
      PUBLIC_IP=$candidate; break
    fi
  done
  if [[ -z "${PUBLIC_IP:-}" ]]; then
    ip -4 -o addr show scope global > "$WORK/interfaces"
    PUBLIC_IP=$(helper public-ip "$WORK/interfaces") || die 'Could not determine this VPS public IPv4.'
  fi
  ADDRESS=$PUBLIC_IP
  if [[ -n "${SERVER_ADDRESS:-}" ]]; then ADDRESS=$(helper address "$SERVER_ADDRESS" "$PUBLIC_IP"); fi
  say "Client address: $ADDRESS (detected public IPv4: $PUBLIC_IP)"
}
proxy_requests() {
  local socks_port=$1 url code round selected=''
  for url in https://www.gstatic.com/generate_204 https://www.microsoft.com/ https://example.com/; do
    if code=$(curl -q -fsS --proxy "socks5h://127.0.0.1:$socks_port" --noproxy '' \
      --connect-timeout 7 --max-time 18 -o /dev/null -w '%{http_code}' "$url" 2>"$WORK/https-error") &&
       [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then selected=$url; break; fi
  done
  [[ -n "$selected" ]] || return 1
  for round in 1 2; do
    code=$(curl -q -fsS --proxy "socks5h://127.0.0.1:$socks_port" --noproxy '' \
      --connect-timeout 7 --max-time 18 -o /dev/null -w '%{http_code}' "$selected" 2>"$WORK/https-error") || return 1
    [[ "$code" =~ ^[23][0-9][0-9]$ ]] || return 1
  done
  say "PASS: 3 independent HTTPS requests through REALITY/Vision ($selected)."
}
test_proxy() {
  local state=$1 remote_port=$2 start_server=$3 socks_port
  stop_pair
  if [[ "$start_server" == 1 ]]; then
    helper server "$state" 127.0.0.1 "$remote_port" > "$WORK/test-server.json" || return 1
    "$XRAY" run -test -config "$WORK/test-server.json" >"$WORK/config-test.log" 2>&1 || return 1
    "$XRAY" run -config "$WORK/test-server.json" >"$WORK/server.log" 2>&1 9>&- &
    SERVER_PID=$!
    wait_listener "$remote_port" "$SERVER_PID" || { stop_pair; return 1; }
  fi
  socks_port=$(helper free-port) || { stop_pair; return 1; }
  helper client "$state" 127.0.0.1 "$remote_port" "$socks_port" > "$WORK/test-client.json" || { stop_pair; return 1; }
  "$XRAY" run -test -config "$WORK/test-client.json" >"$WORK/client-config-test.log" 2>&1 || { stop_pair; return 1; }
  "$XRAY" run -config "$WORK/test-client.json" >"$WORK/client.log" 2>&1 9>&- &
  CLIENT_PID=$!
  if ! wait_listener "$socks_port" "$CLIENT_PID" || ! proxy_requests "$socks_port"; then
    stop_pair; return 1
  fi
  stop_pair
}
choose_target() {
  local name ip test_port candidates
  candidates="${SNI:-www.microsoft.com www.amazon.com dl.google.com www.bing.com}"
  for name in $candidates; do
    helper hostname "$name" >/dev/null || return 1
    say "Testing REALITY target: $name"
    if ! helper resolve "$name" > "$WORK/target-ips"; then continue; fi
    ip=$(head -n 1 "$WORK/target-ips")
    [[ -n "$ip" ]] || continue
    if ! timeout 22 "$XRAY" tls ping -ip "$ip" "$name" >"$WORK/tls-ping.log" 2>&1; then
      say "Target did not complete its TLS probe: $name"; continue
    fi
    if ! awk '/^Pinging with SNI/{part=1} part && /TLS Version:[[:space:]]+TLS 1.3/{ok=1} END{exit !ok}' "$WORK/tls-ping.log"; then
      say "Target did not pass verified TLS 1.3: $name"; continue
    fi
    helper state "$WORK/keys" "$WORK/uuid" "$ADDRESS" "$PORT" "$name" "$CORE_VERSION" "$FINGERPRINT" > "$WORK/state.json"
    test_port=$(helper free-port)
    if test_proxy "$WORK/state.json" "$test_port" 1; then
      say "Selected and proxy-tested target: $name"; return 0
    fi
    say "Target failed the real proxy test: $name"
  done
  die 'No target passed TLS 1.3 plus real REALITY/Vision HTTPS tests. Nothing was installed.'
}
allow_firewall() {
  local iface rc
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld.service; then
    FW_KIND=firewalld
    iface=$(ip -4 route show default | awk 'NR==1 {for(i=1;i<NF;i++)if($i=="dev"){print $(i+1);exit}}')
    FW_ZONE=$(firewall-cmd --get-zone-of-interface="$iface" 2>/dev/null || true)
    if [[ -z "$FW_ZONE" || "$FW_ZONE" == 'no zone' ]]; then FW_ZONE=$(firewall-cmd --get-default-zone); fi
    [[ "$FW_ZONE" =~ ^[A-Za-z0-9_-]+$ ]] || die 'Could not identify the active firewalld zone.'
    if firewall-cmd --zone="$FW_ZONE" --query-port="$PORT/tcp" >/dev/null; then :; else
      rc=$?; [[ "$rc" == 1 ]] || die 'firewalld runtime query failed.'
      FW_RUNTIME=1; firewall-cmd --zone="$FW_ZONE" --add-port="$PORT/tcp" >/dev/null
    fi
    if firewall-cmd --permanent --zone="$FW_ZONE" --query-port="$PORT/tcp" >/dev/null; then :; else
      rc=$?; [[ "$rc" == 1 ]] || die 'firewalld permanent query failed.'
      FW_PERMANENT=1; firewall-cmd --permanent --zone="$FW_ZONE" --add-port="$PORT/tcp" >/dev/null
    fi
  elif command -v ufw >/dev/null 2>&1 && ufw status | awk '/^Status: active$/{yes=1}END{exit !yes}'; then
    FW_KIND=ufw
    if ! ufw status | awk -v p="$PORT" '$1==p"/tcp" && /ALLOW/ {yes=1} END{exit !yes}'; then
      FW_ADDED=1; ufw allow "$PORT/tcp" comment "$OWNER" >/dev/null
    fi
  elif command -v iptables >/dev/null 2>&1; then
    FW_KIND=iptables
    if ! iptables -C INPUT -p tcp --dport "$PORT" -m comment --comment "$OWNER" -j ACCEPT 2>/dev/null; then
      FW_ADDED=1
      iptables -I INPUT 1 -p tcp --dport "$PORT" -m comment --comment "$OWNER" -j ACCEPT
    fi
    save_iptables
  else
    say 'No supported host firewall tool found. Provider firewall still requires TCP access.'
  fi
}
write_unit() {
  cat > "$UNIT" <<SERVICE_UNIT
# Managed by bwh45-reality-v2
[Unit]
Description=bwh45 VLESS REALITY Vision
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN run -config $CONFIG
Restart=on-failure
RestartPreventExitStatus=23
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICE_UNIT
  chmod 644 "$UNIT"
}
guard_owned() {
  local p
  for p in "$BASE" "$LIB" "$UNIT" "$INFO"; do [[ ! -L "$p" ]] || die "Refusing symbolic link: $p"; done
  [[ -f "$BASE/.owner" && ! -L "$BASE/.owner" && $(cat "$BASE/.owner") == "$OWNER" ]] || die 'Unknown or missing installation owner.'
  [[ -f "$STATE" && ! -L "$STATE" && -f "$CONFIG" && ! -L "$CONFIG" && -x "$BIN" && ! -L "$BIN" ]] || die 'Installation is incomplete; inspect its files before retrying.'
  [[ -f "$UNIT" ]] && head -n 1 "$UNIT" | awk '$0=="# Managed by bwh45-reality-v2"{ok=1} END{exit !ok}' || die 'Unknown service unit.'
  helper field "$STATE" port >/dev/null
}
check_installed() {
  guard_owned
  XRAY=$BIN
  PORT=$(helper field "$STATE" port)
  "$XRAY" run -test -config "$CONFIG"
  systemctl is-active --quiet "$SERVICE" || die "Service is not running: $SERVICE"
  test_proxy "$STATE" "$PORT" 0 || {
    journalctl -u "$SERVICE" -n 25 --no-pager >&2 || true
    die 'The installed service failed its real REALITY/Vision proxy test.'
  }
  helper text "$STATE"
  say 'Server-side end-to-end checks passed. Import the link and verify from your client network.'
}
uninstall_owned() {
  guard_owned
  local backup
  backup=$(mktemp -d /root/bwh45-reality-backup.XXXXXX)
  cp -a -- "$BASE" "$backup/config"
  cp -a -- "$UNIT" "$backup/"
  [[ ! -f "$INFO" ]] || cp -a -- "$INFO" "$backup/"
  systemctl stop "$SERVICE"
  systemctl disable "$SERVICE"
  rm -f -- "$UNIT" "$INFO"
  rm -rf -- "$BASE" "$LIB"
  systemctl daemon-reload
  say "Uninstalled. Private configuration backup: $backup"
  say 'Host firewall rules were preserved.'
}
main() {
  local mode=${1:---install} tool path
  case "$mode" in --install|--check|--uninstall) ;; --help) say 'Usage: install.sh [--install|--check|--uninstall]'; return 0;; *) die 'Unknown option.';; esac
  [[ $(id -u) == 0 ]] || die 'Run as root on the bwh45 VPS.'
  [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die 'This installer targets Linux x86_64.'
  [[ -d /run/systemd/system ]] || die 'A running systemd host is required.'
  for tool in curl systemctl ss ip awk sha256sum timeout mktemp install cp chmod head flock; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing command: $tool"
  done
  [[ ! -L /run/bwh45-reality.lock ]] || die 'Unsafe lock path.'
  exec 9>/run/bwh45-reality.lock
  flock -n 9 || die 'Another bwh45 installation/check is running.'
  find_python
  WORK=$(mktemp -d /tmp/bwh45-reality.XXXXXX)
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$mode" == --uninstall ]]; then uninstall_owned; return; fi
  if [[ -e "$BASE" ]]; then
    guard_owned
    if [[ "$mode" == --install ]]; then systemctl start "$SERVICE"; fi
    check_installed; return
  fi
  [[ "$mode" == --install ]] || die 'This installer has not installed a node yet.'
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die 'Invalid PORT.'
  [[ "$FINGERPRINT" == chrome || "$FINGERPRINT" == ios ]] || die 'FINGERPRINT must be chrome or ios.'
  for path in "$BASE" "$LIB" "$UNIT" "$UNIT.d" "$INFO"; do
    [[ ! -e "$path" && ! -L "$path" ]] || die "Existing file requires review: $path"
  done
  if port_busy "$PORT"; then
    ss -lntp >&2
    die "TCP $PORT is occupied. Stop/uninstall its previous owner first."
  fi
  say '[1/7] Downloading and verifying the pinned official Xray core...'
  download_core
  say '[2/7] Detecting this VPS address and generating independent credentials...'
  public_address
  "$XRAY" uuid > "$WORK/uuid"
  "$XRAY" x25519 > "$WORK/keys"
  say '[3/7] Selecting a TLS target and testing real REALITY/Vision HTTPS traffic...'
  choose_target
  say '[4/7] Validating the final server and client configurations...'
  helper server "$WORK/state.json" 0.0.0.0 "$PORT" > "$WORK/config.json"
  helper client "$WORK/state.json" "$ADDRESS" "$PORT" 10808 > "$WORK/export-client.json"
  "$XRAY" run -test -config "$WORK/config.json"
  "$XRAY" run -test -config "$WORK/export-client.json"
  say '[5/7] Installing a dedicated systemd service and allowing its TCP port...'
  install -d -m 700 "$BASE" "$LIB"
  printf '%s\n' "$OWNER" > "$BASE/.owner"
  OWNED=1
  install -m 700 "$XRAY" "$BIN"
  install -m 600 "$WORK/state.json" "$STATE"
  install -m 600 "$WORK/config.json" "$CONFIG"
  install -m 600 "$WORK/export-client.json" "$BASE/client.json"
  write_unit
  allow_firewall
  say '[6/7] Starting the actual service and testing it through a real client...'
  systemctl daemon-reload
  systemctl start "$SERVICE"
  XRAY=$BIN
  for attempt in {1..50}; do
    if systemctl is-active --quiet "$SERVICE" && helper listening "$PORT" >/dev/null 2>&1; then break; fi
    sleep 0.2
  done
  if ! test_proxy "$STATE" "$PORT" 0; then
    journalctl -u "$SERVICE" -n 30 --no-pager >&2 || true
    die 'The actual service failed the end-to-end proxy test.'
  fi
  systemctl is-active --quiet "$SERVICE" || die 'Service stopped after its proxy test.'
  systemctl enable "$SERVICE"
  helper text "$STATE" > "$INFO"
  chmod 600 "$INFO"
  COMMITTED=1
  say '[7/7] Server-side installation and end-to-end tests passed.'
  cat "$INFO"
  say ''
  say "Service: systemctl status $SERVICE --no-pager -l"
  say "Client info: $INFO"
  say 'Now select this new node in v2rayN, enable its system proxy, and test from your network.'
  say 'The VPS self-test does not verify provider firewall rules or the client-to-VPS Internet path.'
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
