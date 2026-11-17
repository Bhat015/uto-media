#!/bin/bash
# One live session: shuffles the stream library into a playlist and streams it on repeat.
# Ends after 11 h 50 m (so YouTube archives the broadcast), or as soon as the library changes
# (a video added or removed), so the next session plays the new set. systemd restarts it 30 s later.
set -euo pipefail
: "${YT_STREAM_KEY:?missing YT_STREAM_KEY in /etc/uto/stream.env}"
LIB=/srv/uto/stream
sig() { ls "$LIB"/*.ts 2>/dev/null | sort | md5sum | cut -d' ' -f1; }
mapfile -t files < <(ls "$LIB"/*.ts 2>/dev/null | shuf)
[ ${#files[@]} -gt 0 ] || { echo "no stream files yet"; sleep 600; exit 1; }
start=$(sig)
echo "session: ${#files[@]} videos: $(printf '%s ' "${files[@]##*/}")"
LIST=$(mktemp)
for i in $(seq 1 300); do for f in "${files[@]}"; do echo "file '$f'"; done; done > "$LIST"
ffmpeg -nostdin -v warning -re -f concat -safe 0 -i "$LIST" -t 42600 \
  -c copy -bsf:a aac_adtstoasc -f flv "rtmps://a.rtmps.youtube.com:443/live2/$YT_STREAM_KEY" &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$LIST"' EXIT
while kill -0 $pid 2>/dev/null; do
  sleep 60
  if [ "$(sig)" != "$start" ]; then echo "library changed, starting a new session"; kill $pid; wait $pid 2>/dev/null || true; exit 0; fi
done
wait $pid
