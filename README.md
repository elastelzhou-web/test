# CentOS 7 Xray / REALITY installer and v2ray manager

Version 3.0.0. Supports Linux x86_64 and systemd, including CentOS 7 / Bash 4.2 / Python 2.7. The core is Xray; the command name is v2ray for familiar administration.

## Install or upgrade an existing v2 installation

~~~bash
bash <(curl -fsSL https://raw.githubusercontent.com/elastelzhou-web/test/main/install.sh)
~~~

An existing installation created by this repository is upgraded in place. UUID, REALITY private/public keys, ShortId, selected target and core are preserved. A different program's v2ray command is never silently overwritten. The immutable v2 installer at commit 0540b951e0c9d645ce3cbf9f4271e3d296e87524 remains unchanged.

Fresh installations use official Xray v26.3.27 with its pinned official SHA256, detect the current public IPv4, select a target by verified TLS 1.3 plus actual REALITY/Vision HTTPS requests, and check the actual systemd service again. The target defaults exclude Microsoft's documented incompatible certificate-record shape: https://github.com/XTLS/Xray-core/issues/6356

## Commands (run as root)

| Command | Behavior |
| --- | --- |
| v2ray info | Show REALITY connection information and VLESS import URI |
| v2ray config | Edit port, address, target/SNI, fingerprint, name, UUID, or rotate keys |
| v2ray link | Temporary HTTPS link to complete Xray client JSON |
| v2ray infolink | Temporary HTTPS link to client information |
| v2ray qr | Temporary HTTPS REALITY QR image link |
| v2ray ss | Enable, edit, or disable Shadowsocks; disabled until requested |
| v2ray ssinfo | Show SS information and SIP002 URI |
| v2ray ssqr | Temporary HTTPS SS QR image link |
| v2ray status | Display service state |
| v2ray start / stop / restart | Control the service; start/restart perform proxy checks |
| v2ray log | Last 50 journal lines; append -f to follow |
| v2ray update | Download and verify the official stable Xray core, test, then update; rollback on restart failure |
| v2ray update.sh | Verify this repository's version/hash manifest, then update the manager only |
| v2ray uninstall | Back up configuration and remove the node, sharing service and owned manager |
| v2ray check | Actual proxy self-test |

All requested commands are implemented. They manage Xray and do not install the separate V2Fly core.

Configuration changes are validated with the actual core and a temporary proxy before application. A failed restart restores the previous configuration. Previously stopped services remain stopped. Core/script updates preserve node credentials. Root-only backups are retained under /root/bwh45-reality-backup.*. Existing firewall rules are preserved on uninstall; the manager never flushes rules or changes SSH.

Examples:

~~~bash
v2ray config --port 443 --fingerprint chrome --name my-node
v2ray ss --enable --port 8388
v2ray ssinfo
v2ray ss --disable
v2ray update 26.3.27
~~~

For passwords use the hidden interactive prompt or --password-stdin; do not put secrets in command arguments. SS defaults to 2022-blake3-aes-128-gcm, with TCP and native UDP; aes-256-gcm and chacha20-ietf-poly1305 are also supported. SS2022 links follow SIP002's required percent-encoded userinfo rather than Base64URL.

## HTTPS sharing and QR codes

Sharing commands generate QR SVG images locally. Node information is not sent to an external QR website or uploaded to GitHub.

Temporary HTTPS sharing starts only when link/infolink/qr/ssqr is invoked. Defaults: port 8443, a random 192-bit URL token, and a 10-minute lifetime. Only known client export files are served. Server state, REALITY private keys, directory listings and uploads have no download endpoint. URLs and credentials are not logged. The temporary listener exits on expiry.

**Default certificate is self-signed.** Browsers require a certificate exception: verify the SHA256 fingerprint printed in the SSH session before accepting it. A client downloading JSON must trust that certificate. The node's REALITY listener on 443 is independent. Provider firewall must separately allow the sharing TCP port.

If the openssl command is missing on CentOS 7, the sharing command installs only that dependency using GPG-checked official CentOS 7 vault packages through a temporary repository configuration; it does not rewrite the system repositories.

Optional, for browser-trusted HTTPS, supply your own certificate and corresponding hostname:

~~~bash
SHARE_HOST=share.example.com SHARE_CERT=/path/fullchain.pem SHARE_KEY=/path/privkey.pem v2ray link
~~~

SHARE_PORT and SHARE_TTL override the default port/lifetime (TTL 1..3600 seconds). Do not publish generated credential URLs. Local exports remain root-only in /etc/bwh45-reality/exports.

## Testing

Actions verifies CentOS 7 Bash/Python 2 compatibility, key-format regressions, persistent manager reconstruction, SS2022 URIs, real REALITY and SS TCP/UDP traffic. An Ubuntu systemd runner tests all commands, decodes both QR images independently, verifies HTTPS downloads/expiry/private-key isolation, simulates a failed restart to verify rollback, updates both core/manager, and migrates a real v2 installation without changing its credentials.

This does not guarantee provider firewall policy, the client-to-VPS path, IP reputation, or availability of OpenAI authenticated sessions. Installation on each VPS repeats server-side proxy tests.

## Sources and attribution

- https://github.com/XTLS/Xray-install
- https://github.com/XTLS/REALITY/blob/main/README.en.md
- https://github.com/XTLS/Xray-core/releases/tag/v26.3.27
- https://xtls.github.io/config/inbounds/shadowsocks.html
- https://shadowsocks.org/doc/sip002.html
- User reference: https://github.com/cholf5/random/issues/38
- Command naming reference: xyz690/v2ray and 233boy/v2ray; this is an independent implementation.
- Vendored PyQRCode: https://github.com/mnooner256/pyqrcode at 674a77b5eaf850d063f518bd90c243ee34ad6b5d. BSD-3-Clause copyright/license retained in vendor/pyqrcode and the installed THIRD_PARTY_NOTICES.txt.

No live VPS credentials are stored in this repository or CI files.
