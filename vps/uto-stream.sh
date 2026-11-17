#!/bin/bash
# One live session: shuffles the stream library into a playlist, streams it on repeat,
# and stops after 11 h 50 m so YouTube can archive the broadcast as a public video.
# systemd restarts it 30 s later for the next session.
set -euo pipefail
: "${YT_STREAM_KEY:?missing YT_STREAM_KEY in /etc/uto/stream.env}"
LIB=/srv/uto/stream
mapfile -t files < <(ls "$LIB"/*.ts 2>/dev/null | shuf)
[ ${#files[@]} -gt 0 ] || { echo "no stream files yet"; sleep 600; exit 1; }
LIST=$(mktemp)
for i in $(seq 1 200); do for f in "${files[@]}"; do echo "file '$f'"; done; done > "$LIST"
exec ffmpeg -nostdin -v warning -re -f concat -safe 0 -i "$LIST" -t 42600 \
  -c copy -bsf:a aac_adtstoasc -f flv "rtmps://a.rtmps.youtube.com:443/live2/$YT_STREAM_KEY"
