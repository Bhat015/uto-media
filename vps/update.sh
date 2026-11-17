#!/bin/bash
# One-time upgrade (run as root): the server scripts now update themselves from GitHub,
# and the live loop restarts with the new set whenever a video is added or removed.
set -euo pipefail
RAW=https://raw.githubusercontent.com/Bhat015/uto-media/main/vps
install -d -o uto -g uto /srv/uto/bin
for f in uto-sync.sh uto-stream.sh; do
  curl -fsSL "$RAW/$f?$(date +%s)" -o /srv/uto/bin/$f; chmod 755 /srv/uto/bin/$f; chown uto:uto /srv/uto/bin/$f
  printf '#!/bin/bash\nexec /srv/uto/bin/%s "$@"\n' "$f" > /usr/local/bin/$f; chmod 755 /usr/local/bin/$f
done
systemctl start uto-sync.service || true
systemctl restart uto-stream.service
echo "Updated. Stream library now:"; ls -1 /srv/uto/stream
