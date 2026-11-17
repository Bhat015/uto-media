#!/bin/bash
# Under the Ordinary — stream + media server setup (Ubuntu 24.04, run once as root).
#   curl -fsSL https://raw.githubusercontent.com/Bhat015/uto-media/main/vps/setup_vps.sh | sudo bash
#
# Installs:
#   uto-sync.timer   every 5 min: reads manifest.json from uto-media, downloads new videos
#                    (stored in <100 MB parts on GitHub), verifies sha256, makes a stream copy.
#   Caddy            serves /srv/uto/public over HTTPS at https://<ip-with-dashes>.sslip.io
#                    (vidIQ imports large files such as compilations from here).
#   uto-stream       24/7 YouTube Live loop of the stream copies, restarted every 11 h 50 m
#                    so YouTube archives each segment. Installed DISABLED; enable it when
#                    the library has a few hours of video.
# Needs /etc/uto/stream.env containing YT_STREAM_KEY=... (only for uto-stream).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
RAW=https://raw.githubusercontent.com/Bhat015/uto-media/main/vps

apt-get update -qq
apt-get install -y -qq ffmpeg curl jq debian-keyring debian-archive-keyring apt-transport-https gnupg >/dev/null
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy >/dev/null
fi

id uto >/dev/null 2>&1 || useradd --system --home /srv/uto --shell /usr/sbin/nologin uto
install -d -o uto -g uto /srv/uto /srv/uto/public /srv/uto/stream /srv/uto/parts
install -d -m 700 /etc/uto
for f in uto-sync.sh uto-stream.sh; do curl -fsSL "$RAW/$f" -o /usr/local/bin/$f; chmod 755 /usr/local/bin/$f; done

# HTTPS host name from the public IPv4 (sslip.io resolves a-b-c-d.sslip.io to a.b.c.d)
IP=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '[:space:]')
HOST="${IP//./-}.sslip.io"
cat > /etc/caddy/Caddyfile <<EOF
$HOST {
    root * /srv/uto/public
    file_server
    header Cache-Control "no-store"
}
EOF
systemctl reload caddy || systemctl restart caddy

cat > /etc/systemd/system/uto-sync.service <<'EOF'
[Unit]
Description=Under the Ordinary media sync
[Service]
Type=oneshot
User=uto
Nice=10
ExecStart=/usr/local/bin/uto-sync.sh
EOF
cat > /etc/systemd/system/uto-sync.timer <<'EOF'
[Unit]
Description=Run uto-sync every 5 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/uto-stream.service <<'EOF'
[Unit]
Description=Under the Ordinary 24/7 YouTube Live loop
After=network-online.target
Wants=network-online.target
[Service]
User=uto
EnvironmentFile=/etc/uto/stream.env
ExecStart=/usr/local/bin/uto-stream.sh
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now uto-sync.timer

echo
echo "Setup done."
echo "  Media URL : https://$HOST/   (first HTTPS request may take ~30 s while the certificate is issued)"
echo "  Sync logs : journalctl -u uto-sync -n 50"
echo "  Stream    : installed but OFF. When ready: sudo systemctl enable --now uto-stream"
