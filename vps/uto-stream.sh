#!/bin/bash
# One live session: creates the next YouTube broadcast (auto-start), shuffles the stream library
# into a playlist and streams it on repeat. Ends after 11 h 50 m so YouTube archives the broadcast
# (only streams under 12 h are archived); systemd starts the next session 30 s later.
# New videos join at the next session (restarting mid-session would cut the broadcast short).
set -euo pipefail
: "${YT_STREAM_KEY:?missing YT_STREAM_KEY in /etc/uto/stream.env}"
LIB=/srv/uto/stream
mapfile -t files < <(ls "$LIB"/*.ts 2>/dev/null | shuf)
[ ${#files[@]} -gt 0 ] || { echo "no stream files yet"; sleep 600; exit 1; }
# a fresh broadcast for this session (YouTube doesn't make one after the previous ends)
python3 /srv/uto/bin/uto-broadcast.py new || echo "WARNING: could not create the next broadcast; open Live Control Room > Stream"
echo "session: ${#files[@]} videos: $(printf '%s ' "${files[@]##*/}")"
LIST=$(mktemp)
for i in $(seq 1 300); do for f in "${files[@]}"; do echo "file '$f'"; done; done > "$LIST"
trap 'rm -f "$LIST"' EXIT
ffmpeg -nostdin -v error -re -f concat -safe 0 -i "$LIST" -t 42600 \
  -c copy -bsf:a aac_adtstoasc -f flv "rtmps://a.rtmps.youtube.com:443/live2/$YT_STREAM_KEY"
